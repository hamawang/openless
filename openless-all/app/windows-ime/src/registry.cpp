#include "registry.h"

#include <msctf.h>
#include <strsafe.h>

#include "guids.h"

namespace {

constexpr wchar_t kClsidKey[] =
    L"Software\\Classes\\CLSID\\{6B9F3F4F-5EE7-42D6-9C61-9F80B03A5D7D}";
constexpr wchar_t kInprocServer32Key[] =
    L"Software\\Classes\\CLSID\\{6B9F3F4F-5EE7-42D6-9C61-9F80B03A5D7D}\\InprocServer32";

HRESULT HResultFromWin32Error(LSTATUS status) {
  return status == ERROR_SUCCESS ? S_OK : HRESULT_FROM_WIN32(status);
}

HRESULT SetStringValue(HKEY key, const wchar_t* name, const wchar_t* value) {
  const auto byte_count =
      static_cast<DWORD>((wcslen(value) + 1) * sizeof(wchar_t));
  return HResultFromWin32Error(
      RegSetValueExW(key, name, 0, REG_SZ,
                     reinterpret_cast<const BYTE*>(value), byte_count));
}

HRESULT RegisterComServer(HINSTANCE module) {
  wchar_t module_path[MAX_PATH] = {};
  const DWORD path_len =
      GetModuleFileNameW(module, module_path, ARRAYSIZE(module_path));
  if (path_len == 0) {
    return HRESULT_FROM_WIN32(GetLastError());
  }
  if (path_len == ARRAYSIZE(module_path)) {
    return HRESULT_FROM_WIN32(ERROR_INSUFFICIENT_BUFFER);
  }

  HKEY clsid_key = nullptr;
  LSTATUS status =
      RegCreateKeyExW(HKEY_CURRENT_USER, kClsidKey, 0, nullptr,
                      REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr, &clsid_key,
                      nullptr);
  HRESULT hr = HResultFromWin32Error(status);
  if (FAILED(hr)) {
    return hr;
  }

  hr = SetStringValue(clsid_key, nullptr, kOpenLessImeName);
  RegCloseKey(clsid_key);
  if (FAILED(hr)) {
    return hr;
  }

  HKEY inproc_key = nullptr;
  status = RegCreateKeyExW(HKEY_CURRENT_USER, kInprocServer32Key, 0, nullptr,
                           REG_OPTION_NON_VOLATILE, KEY_WRITE, nullptr,
                           &inproc_key, nullptr);
  hr = HResultFromWin32Error(status);
  if (FAILED(hr)) {
    return hr;
  }

  hr = SetStringValue(inproc_key, nullptr, module_path);
  if (SUCCEEDED(hr)) {
    hr = SetStringValue(inproc_key, L"ThreadingModel", L"Apartment");
  }
  RegCloseKey(inproc_key);
  return hr;
}

HRESULT DeleteComServerRegistration() {
  const LSTATUS status = RegDeleteTreeW(HKEY_CURRENT_USER, kClsidKey);
  if (status == ERROR_FILE_NOT_FOUND) {
    return S_OK;
  }
  return HResultFromWin32Error(status);
}

class ScopedComInit {
 public:
  ScopedComInit() : hr_(CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED)) {}
  ScopedComInit(const ScopedComInit&) = delete;
  ScopedComInit& operator=(const ScopedComInit&) = delete;
  ~ScopedComInit() {
    if (hr_ == S_OK || hr_ == S_FALSE) {
      CoUninitialize();
    }
  }

  HRESULT hr() const {
    return hr_ == RPC_E_CHANGED_MODE ? S_OK : hr_;
  }

 private:
  HRESULT hr_;
};

HRESULT CreateProfiles(ITfInputProcessorProfiles** profiles) {
  return CoCreateInstance(CLSID_TF_InputProcessorProfiles, nullptr,
                          CLSCTX_INPROC_SERVER,
                          IID_ITfInputProcessorProfiles,
                          reinterpret_cast<void**>(profiles));
}

HRESULT RegisterLanguageProfile() {
  ScopedComInit com;
  HRESULT hr = com.hr();
  if (FAILED(hr)) {
    return hr;
  }

  ITfInputProcessorProfiles* profiles = nullptr;
  hr = CreateProfiles(&profiles);
  if (FAILED(hr)) {
    return hr;
  }

  hr = profiles->Register(CLSID_OpenLessTextService);
  if (SUCCEEDED(hr)) {
    hr = profiles->AddLanguageProfile(
        CLSID_OpenLessTextService, kOpenLessLangId, GUID_OpenLessProfile,
        const_cast<wchar_t*>(kOpenLessImeName),
        static_cast<ULONG>(ARRAYSIZE(kOpenLessImeName) - 1), nullptr, 0, 0);
  }
  if (SUCCEEDED(hr)) {
    hr = profiles->EnableLanguageProfile(CLSID_OpenLessTextService,
                                         kOpenLessLangId, GUID_OpenLessProfile,
                                         TRUE);
  }

  profiles->Release();
  return hr;
}

HRESULT UnregisterLanguageProfile() {
  ScopedComInit com;
  HRESULT hr = com.hr();
  if (FAILED(hr)) {
    return hr;
  }

  ITfInputProcessorProfiles* profiles = nullptr;
  hr = CreateProfiles(&profiles);
  if (FAILED(hr)) {
    return hr;
  }

  hr = profiles->Unregister(CLSID_OpenLessTextService);
  profiles->Release();
  return hr;
}

}  // namespace

HRESULT RegisterOpenLessTextService(HINSTANCE module) {
  if (module == nullptr) {
    return E_INVALIDARG;
  }

  HRESULT hr = RegisterComServer(module);
  if (FAILED(hr)) {
    return hr;
  }

  hr = RegisterLanguageProfile();
  if (FAILED(hr)) {
    DeleteComServerRegistration();
  }
  return hr;
}

HRESULT UnregisterOpenLessTextService() {
  const HRESULT profile_hr = UnregisterLanguageProfile();
  const HRESULT registry_hr = DeleteComServerRegistration();
  return FAILED(profile_hr) ? profile_hr : registry_hr;
}
