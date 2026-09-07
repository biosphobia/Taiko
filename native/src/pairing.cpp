#include "pairing.h"
#include "move_device.h"
#include <cstring>
#include <chrono>

#ifdef TAIKO_WINDOWS
#include <windows.h>
#include <winsock2.h>
#include <bthsdpdef.h>
#include <bluetoothapis.h>
#ifndef BLUETOOTH_SERVICE_ENABLE
#define BLUETOOTH_SERVICE_ENABLE 0x01
#endif
#include <vector>
// {00001124-0000-1000-8000-00805F9B34FB}: Bluetooth HID service class (not instantiated by mingw's headers).
static const GUID HID_SERVICE_GUID = { 0x00001124, 0x0000, 0x1000, { 0x80, 0x00, 0x00, 0x80, 0x5F, 0x9B, 0x34, 0xFB } };
#endif

namespace taiko {

PairingSession::~PairingSession() { cancel(); }

void PairingSession::set(int step, const std::string &msg, bool done, bool success) {
	std::lock_guard<std::mutex> lk(mtx);
	st.step = step;
	st.message = msg;
	st.done = done;
	st.success = success;
	if (done) st.active = false;
}

PairingStatus PairingSession::status() {
	std::lock_guard<std::mutex> lk(mtx);
	return st;
}

void PairingSession::cancel() {
	cancel_flag.store(true);
	if (worker.joinable()) worker.join();
	std::lock_guard<std::mutex> lk(mtx);
	if (st.active) { st.active = false; st.done = true; st.success = false; st.message = "Cancelled"; }
}

#ifdef TAIKO_WINDOWS
bool PairingSession::supported() { return true; }

bool PairingSession::is_elevated() {
	BOOL ret = FALSE;
	HANDLE token = NULL;
	if (OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &token)) {
		TOKEN_ELEVATION elev;
		DWORD size = sizeof(elev);
		if (GetTokenInformation(token, TokenElevation, &elev, sizeof(elev), &size)) ret = elev.TokenIsElevated;
		CloseHandle(token);
	}
	return ret != FALSE;
}

static bool first_radio(HANDLE &radio) {
	BLUETOOTH_FIND_RADIO_PARAMS params;
	params.dwSize = sizeof(params);
	HBLUETOOTH_RADIO_FIND find = BluetoothFindFirstRadio(&params, &radio);
	if (!find) return false;
	BluetoothFindRadioClose(find);
	return true;
}

bool PairingSession::get_host_bt_address(uint8_t out[6], std::string &err) {
	HANDLE radio = NULL;
	if (!first_radio(radio) || !radio) { err = "No Bluetooth adapter found (is Bluetooth turned on?)"; return false; }
	BLUETOOTH_RADIO_INFO info;
	info.dwSize = sizeof(info);
	if (BluetoothGetRadioInfo(radio, &info) != ERROR_SUCCESS) { CloseHandle(radio); err = "BluetoothGetRadioInfo failed"; return false; }
	for (int i = 0; i < 6; i++) out[i] = info.address.rgBytes[i];
	CloseHandle(radio);
	return true;
}

static bool find_device(HANDLE radio, const BLUETOOTH_ADDRESS &addr, BLUETOOTH_DEVICE_INFO &info, bool inquire) {
	BLUETOOTH_DEVICE_SEARCH_PARAMS sp;
	memset(&sp, 0, sizeof(sp));
	sp.dwSize = sizeof(sp);
	sp.cTimeoutMultiplier = 1;
	sp.fIssueInquiry = inquire ? TRUE : FALSE;
	sp.fReturnAuthenticated = TRUE;
	sp.fReturnConnected = TRUE;
	sp.fReturnRemembered = TRUE;
	sp.fReturnUnknown = TRUE;
	sp.hRadio = radio;
	memset(&info, 0, sizeof(info));
	info.dwSize = sizeof(info);
	HBLUETOOTH_DEVICE_FIND find = BluetoothFindFirstDevice(&sp, &info);
	if (!find) return false;
	bool found = false;
	do {
		if (info.Address.ullLong == addr.ullLong) { found = true; break; }
	} while (BluetoothFindNextDevice(find, &info));
	BluetoothFindDeviceClose(find);
	return found;
}

static bool hid_service_enabled(HANDLE radio, BLUETOOTH_DEVICE_INFO &info) {
	DWORD n = 0;
	DWORD r = BluetoothEnumerateInstalledServices(radio, &info, &n, NULL);
	if (r != ERROR_SUCCESS && r != ERROR_MORE_DATA) return false;
	if (n == 0) return false;
	std::vector<GUID> list(n);
	if (BluetoothEnumerateInstalledServices(radio, &info, &n, list.data()) != ERROR_SUCCESS) return false;
	GUID hid = HID_SERVICE_GUID;
	for (DWORD i = 0; i < n; i++) if (IsEqualGUID(list[i], hid)) return true;
	return false;
}

static bool patch_registry(const BLUETOOTH_ADDRESS &move, const BLUETOOTH_ADDRESS &radio) {
	char sub[512];
	snprintf(sub, sizeof(sub), "SYSTEM\\CurrentControlSet\\Services\\HidBth\\Parameters\\Devices\\%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x",
			radio.rgBytes[5], radio.rgBytes[4], radio.rgBytes[3], radio.rgBytes[2], radio.rgBytes[1], radio.rgBytes[0],
			move.rgBytes[5], move.rgBytes[4], move.rgBytes[3], move.rgBytes[2], move.rgBytes[1], move.rgBytes[0]);
	HKEY key;
	DWORD disp;
	LONG res = RegCreateKeyExA(HKEY_LOCAL_MACHINE, sub, 0, NULL, 0, KEY_READ | KEY_QUERY_VALUE | KEY_WOW64_64KEY | KEY_ALL_ACCESS, NULL, &key, &disp);
	if (res != ERROR_SUCCESS) return false;
	DWORD data = 1;
	bool ok = RegSetValueExA(key, "VirtuallyCabled", 0, REG_DWORD, (const BYTE *)&data, sizeof(data)) == ERROR_SUCCESS;
	RegCloseKey(key);
	return ok;
}

struct AuthState {
	HANDLE radio;
	BLUETOOTH_DEVICE_INFO *info;
	HANDLE done_event;
};

static BOOL CALLBACK auth_callback(LPVOID param, PBLUETOOTH_AUTHENTICATION_CALLBACK_PARAMS p) {
	AuthState *s = (AuthState *)param;
	BLUETOOTH_AUTHENTICATE_RESPONSE resp;
	memset(&resp, 0, sizeof(resp));
	resp.authMethod = p->authenticationMethod;
	resp.bthAddressRemote = p->deviceInfo.Address;
	resp.negativeResponse = FALSE;
	if (BluetoothSendAuthenticationResponseEx(s->radio, &resp) == ERROR_SUCCESS) s->info->fAuthenticated = TRUE;
	SetEvent(s->done_event);
	return TRUE;
}

static bool authenticate(HANDLE radio, BLUETOOTH_DEVICE_INFO &info) {
	if (info.fAuthenticated) return true;
	AuthState state{ radio, &info, CreateEventA(NULL, TRUE, FALSE, NULL) };
	HBLUETOOTH_AUTHENTICATION_REGISTRATION reg = 0;
	bool ok = false;
	if (BluetoothRegisterForAuthenticationEx(&info, &reg, &auth_callback, &state) == ERROR_SUCCESS) {
		DWORD r = BluetoothAuthenticateDeviceEx(NULL, radio, &info, NULL, MITMProtectionNotRequiredBonding);
		if (r == ERROR_NO_MORE_ITEMS) ok = true;
		else if (r == ERROR_SUCCESS || r == ERROR_IO_PENDING) {
			WaitForSingleObject(state.done_event, 15000);
			ok = info.fAuthenticated != FALSE;
		}
		BluetoothUnregisterAuthentication(reg);
	}
	CloseHandle(state.done_event);
	return ok;
}

void PairingSession::run() {
	HANDLE radio = NULL;
	if (!first_radio(radio) || !radio) { set(3, "No Bluetooth adapter found", true, false); return; }
	BLUETOOTH_RADIO_INFO rinfo;
	rinfo.dwSize = sizeof(rinfo);
	if (BluetoothGetRadioInfo(radio, &rinfo) != ERROR_SUCCESS) { CloseHandle(radio); set(3, "Cannot read Bluetooth adapter info", true, false); return; }
	if (!BluetoothIsConnectable(radio)) BluetoothEnableIncomingConnections(radio, TRUE);
	if (!BluetoothIsDiscoverable(radio)) BluetoothEnableDiscovery(radio, TRUE);

	BLUETOOTH_ADDRESS move_addr;
	move_addr.ullLong = 0;
	for (int i = 0; i < 6; i++) move_addr.rgBytes[i] = controller_addr[i];

	set(3, "Unplug the USB cable and press the PS button. Keep pressing it whenever the red light stops blinking.");
	int scan = 0;
	auto t_start = std::chrono::steady_clock::now();
	while (!cancel_flag.load()) {
		if (std::chrono::steady_clock::now() - t_start > std::chrono::minutes(3)) { set(3, "Timed out waiting for the controller to connect", true, false); break; }
		BLUETOOTH_DEVICE_INFO info;
		if (find_device(radio, move_addr, info, scan == 0)) {
			if (wcscmp(info.szName, L"Motion Controller") == 0 || info.szName[0] == 0) {
				bool auth_ok = true;
				if (model_type == MODEL_ZCM2) auth_ok = authenticate(radio, info);
				if (auth_ok) {
					for (int attempt = 0; attempt < 60 && !cancel_flag.load(); attempt++) {
						if (BluetoothGetDeviceInfo(radio, &info) != ERROR_SUCCESS) break;
						if (info.fConnected) {
							patch_registry(move_addr, rinfo.address);
							if (!hid_service_enabled(radio, info)) {
								GUID hid = HID_SERVICE_GUID;
								BluetoothSetServiceState(radio, &info, &hid, BLUETOOTH_SERVICE_ENABLE);
								patch_registry(move_addr, rinfo.address);
							}
							// Require several consecutive successful checks (the stack can report a connection early).
							bool stable = true;
							for (int k = 0; k < 5 && stable; k++) {
								if (BluetoothGetDeviceInfo(radio, &info) != ERROR_SUCCESS) { stable = false; break; }
								if (!(info.fConnected && info.fRemembered && hid_service_enabled(radio, info))) stable = false;
								Sleep(300);
							}
							if (stable) {
								CloseHandle(radio);
								set(4, "Controller paired and connected", true, true);
								return;
							}
						}
						Sleep(300);
					}
					if (!info.fConnected) BluetoothRemoveDevice(&info.Address);
				} else {
					set(3, "Authentication failed, retrying. Press the PS button again.");
				}
			}
		}
		for (int i = 0; i < 14 && !cancel_flag.load(); i++) Sleep(100);
		scan = (scan + 1) % 5;
	}
	CloseHandle(radio);
	if (cancel_flag.load()) set(3, "Cancelled", true, false);
}
#else
bool PairingSession::supported() { return false; }
bool PairingSession::is_elevated() { return true; }
bool PairingSession::get_host_bt_address(uint8_t out[6], std::string &err) { (void)out; err = "Pairing is only implemented on Windows"; return false; }
void PairingSession::run() { set(3, "Pairing is only implemented on Windows", true, false); }
#endif

bool PairingSession::begin(MoveDevice *dev, int model) {
	cancel();
	cancel_flag.store(false);
	{
		std::lock_guard<std::mutex> lk(mtx);
		st = PairingStatus();
		st.active = true;
	}
	model_type = model;
	if (!dev || !dev->is_open()) { set(1, "Controller is not connected over USB", true, false); return false; }
	if (dev->is_bluetooth()) { set(1, "This controller is already connected over Bluetooth", true, false); return false; }
	std::string err;
	if (!get_host_bt_address(host_addr, err)) { set(1, err, true, false); return false; }
	uint8_t current_host[6];
	if (!dev->read_bt_addrs(controller_addr, current_host)) { set(1, "Could not read the controller's Bluetooth address over USB", true, false); return false; }
	{
		std::lock_guard<std::mutex> lk(mtx);
		st.controller_addr = MoveDevice::btaddr_to_string(controller_addr);
		st.host_addr = MoveDevice::btaddr_to_string(host_addr);
	}
	set(2, "Writing host address into the controller");
	if (memcmp(current_host, host_addr, 6) != 0) {
		if (!dev->set_host_bt_addr(host_addr)) { set(2, "Failed to write the host address to the controller", true, false); return false; }
	}
	if (!supported()) { set(2, "Host address written. Finish pairing in your OS Bluetooth settings.", true, true); return true; }
	if (!is_elevated()) {
		set(2, "Host address written, but registering the controller with Windows requires running TaikoMove as Administrator.", true, false);
		return false;
	}
	worker = std::thread(&PairingSession::run, this);
	return true;
}

} // namespace taiko
