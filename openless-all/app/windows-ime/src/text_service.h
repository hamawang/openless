#pragma once

#include <msctf.h>
#include <string>
#include <windows.h>

class OpenLessTextService final : public ITfTextInputProcessorEx {
 public:
  OpenLessTextService();
  OpenLessTextService(const OpenLessTextService&) = delete;
  OpenLessTextService& operator=(const OpenLessTextService&) = delete;
  ~OpenLessTextService() override;

  STDMETHODIMP QueryInterface(REFIID iid, void** object) override;
  STDMETHODIMP_(ULONG) AddRef() override;
  STDMETHODIMP_(ULONG) Release() override;

  STDMETHODIMP Activate(ITfThreadMgr* thread_mgr, TfClientId client_id) override;
  STDMETHODIMP Deactivate() override;
  STDMETHODIMP ActivateEx(ITfThreadMgr* thread_mgr,
                          TfClientId client_id,
                          DWORD flags) override;

  HRESULT SubmitTextFromPipe(const std::wstring& session_id,
                             const std::wstring& text);

 private:
  HRESULT StartIpcServer();
  void StopIpcServer();

  LONG ref_count_ = 1;
  ITfThreadMgr* thread_mgr_ = nullptr;
  TfClientId client_id_ = TF_CLIENTID_NULL;
};
