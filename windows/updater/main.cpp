#include <windows.h>
#include <shlobj.h>
#include <tlhelp32.h>
#include <restartmanager.h>

#include <algorithm>
#include <filesystem>
#include <iostream>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace fs = std::filesystem;
constexpr wchar_t kExe[] = L"holistic_anecdotal_records.exe";

// Handles pin directories against rename/deletion and files against concurrent
// writes. No path-based overwrite or recursive deletion is used.
class Handle {
 public:
  explicit Handle(HANDLE h = INVALID_HANDLE_VALUE) : h_(h) {}
  ~Handle() { if (valid()) CloseHandle(h_); }
  Handle(const Handle&) = delete;
  Handle& operator=(const Handle&) = delete;
  Handle(Handle&& other) noexcept : h_(std::exchange(other.h_, INVALID_HANDLE_VALUE)) {}
  Handle& operator=(Handle&& other) noexcept {
    if (valid()) CloseHandle(h_);
    h_ = std::exchange(other.h_, INVALID_HANDLE_VALUE);
    return *this;
  }
  bool valid() const { return h_ != INVALID_HANDLE_VALUE && h_ != nullptr; }
  HANDLE get() const { return h_; }
 private:
  HANDLE h_;
};

[[noreturn]] void fail(const char* message) { throw std::runtime_error(message); }
[[noreturn]] void winFail(const char* message) {
  throw std::runtime_error(std::string(message) + " (Windows error " +
                           std::to_string(GetLastError()) + ")");
}
void log(const char* message) { std::cout << message << std::endl; }
bool equal(const fs::path& a, const fs::path& b) {
  return CompareStringOrdinal(a.c_str(), -1, b.c_str(), -1, TRUE) == CSTR_EQUAL;
}
bool within(const fs::path& child, const fs::path& parent) {
  auto c = child.begin();
  for (auto p = parent.begin(); p != parent.end(); ++p, ++c) {
    if (c == child.end() || !equal(*c, *p)) return false;
  }
  return true;
}
fs::path normalized(const fs::path& input) {
  const auto s = input.wstring();
  if (s.size() < 3 || s[1] != L':' || (s[2] != L'\\' && s[2] != L'/') ||
      s.find(L':', 2) != std::wstring::npos) {
    fail("Paths must be absolute local drive paths (no UNC/device paths or streams).");
  }
  auto result = input.lexically_normal();
  while (result != result.root_path() && result.filename().empty()) result = result.parent_path();
  if (GetDriveTypeW(result.root_path().c_str()) != DRIVE_FIXED) fail("Use a local fixed drive.");
  for (const auto& part : result.relative_path()) {
    auto name = part.wstring();
    if (name.empty() || name.back() == L'.' || name.back() == L' ') fail("Ambiguous path component.");
  }
  return result;
}
fs::path finalPath(HANDLE handle) {
  std::wstring buffer(32768, L'\0');
  DWORD count = GetFinalPathNameByHandleW(handle, buffer.data(), static_cast<DWORD>(buffer.size()), FILE_NAME_NORMALIZED);
  if (!count || count >= buffer.size()) winFail("Cannot resolve canonical path");
  buffer.resize(count);
  if (buffer.rfind(L"\\\\?\\", 0) != 0) fail("Unexpected canonical path.");
  return normalized(buffer.substr(4));
}
Handle openChecked(const fs::path& path, bool directory, DWORD access, DWORD share) {
  Handle handle(CreateFileW(path.c_str(), access, share, nullptr, OPEN_EXISTING,
                           FILE_FLAG_OPEN_REPARSE_POINT | FILE_FLAG_BACKUP_SEMANTICS, nullptr));
  if (!handle.valid()) winFail("Cannot open path exclusively enough for a safe update");
  BY_HANDLE_FILE_INFORMATION info{};
  if (!GetFileInformationByHandle(handle.get(), &info)) winFail("Cannot inspect path");
  if (info.dwFileAttributes & FILE_ATTRIBUTE_REPARSE_POINT) fail("Reparse points, junctions and symbolic links are not allowed.");
  if (!!(info.dwFileAttributes & FILE_ATTRIBUTE_DIRECTORY) != directory) fail("Unexpected file/directory type.");
  if (!directory && info.nNumberOfLinks != 1) fail("Hard-linked files are not allowed.");
  if (!equal(finalPath(handle.get()), path)) fail("Path alias or canonical path mismatch.");
  return handle;
}
void pinAncestors(const fs::path& path, std::vector<Handle>& pins) {
  auto current = path.root_path();
  pins.push_back(openChecked(current, true, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE));
  for (const auto& part : path.relative_path()) {
    current /= part;
    pins.push_back(openChecked(current, true, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE));
  }
}
fs::path knownFolder(REFKNOWNFOLDERID id) {
  PWSTR raw = nullptr;
  HRESULT hr = SHGetKnownFolderPath(id, KF_FLAG_DONT_VERIFY, nullptr, &raw);
  if (FAILED(hr)) fail("Cannot determine protected Windows folders.");
  fs::path result(raw);
  CoTaskMemFree(raw);
  return normalized(result);
}
void rejectProtected(const fs::path& app) {
  if (app == app.root_path()) fail("A drive root is not an application directory.");
  // Exact roots (and their ancestors) are unsafe; ordinary installation
  // subdirectories within Program Files or the profile remain possible.
  std::vector<fs::path> roots = {knownFolder(FOLDERID_Profile), knownFolder(FOLDERID_Documents),
      knownFolder(FOLDERID_Desktop), knownFolder(FOLDERID_Downloads),
      knownFolder(FOLDERID_ProgramFiles), knownFolder(FOLDERID_ProgramFilesX86),
      knownFolder(FOLDERID_Public)};
  std::vector<fs::path> trees = {knownFolder(FOLDERID_Windows), knownFolder(FOLDERID_ProgramData),
      knownFolder(FOLDERID_RoamingAppData), knownFolder(FOLDERID_LocalAppData),
      knownFolder(FOLDERID_LocalAppDataLow),
      knownFolder(FOLDERID_Documents) / L"HolisticAnecdotalRecords",
      knownFolder(FOLDERID_Profile) / L"Documents" / L"HolisticAnecdotalRecords"};
  auto check = [&](const fs::path& protectedPath, bool tree) {
    if (within(protectedPath, app) || (tree && within(app, protectedPath))) fail("Target intersects a protected system or user-data location.");
    // Known folders may be redirected. Check their resolved paths as well.
    Handle h(CreateFileW(protectedPath.c_str(), FILE_READ_ATTRIBUTES,
        FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING,
        FILE_FLAG_BACKUP_SEMANTICS, nullptr));
    if (h.valid()) {
      auto resolved = finalPath(h.get());
      if (within(resolved, app) || (tree && within(app, resolved))) fail("Target intersects a resolved protected location.");
    } else if (GetLastError() != ERROR_FILE_NOT_FOUND && GetLastError() != ERROR_PATH_NOT_FOUND) {
      winFail("Cannot verify protected location");
    }
  };
  for (const auto& root : roots) check(root, false);
  for (const auto& tree : trees) check(tree, true);
}
void requireBundle(const fs::path& root) {
  if (!fs::is_regular_file(root / kExe) || !fs::is_regular_file(root / L"flutter_windows.dll") ||
      !fs::is_regular_file(root / L"data" / L"icudtl.dat") ||
      !fs::is_directory(root / L"data" / L"flutter_assets")) {
    fail("Both directories must contain the application exe, flutter_windows.dll, data/icudtl.dat and data/flutter_assets.");
  }
}
struct Tree {
  std::vector<fs::path> directories;
  std::vector<fs::path> files;
};
Tree inspectTree(const fs::path& root, std::vector<Handle>& pins) {
  Tree tree;
  for (const auto& entry : fs::directory_iterator(root)) {
    auto path = normalized(entry.path());
    DWORD attrs = GetFileAttributesW(path.c_str());
    if (attrs == INVALID_FILE_ATTRIBUTES) winFail("Cannot inspect bundle entry");
    bool directory = (attrs & FILE_ATTRIBUTE_DIRECTORY) != 0;
    auto handle = openChecked(path, directory, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE);
    if (directory) {
      pins.push_back(std::move(handle));
      tree.directories.push_back(path);
      auto nested = inspectTree(path, pins);
      tree.directories.insert(tree.directories.end(), nested.directories.begin(), nested.directories.end());
      tree.files.insert(tree.files.end(), nested.files.begin(), nested.files.end());
    } else {
      tree.files.push_back(path);
    }
  }
  return tree;
}
fs::path processImage(HANDLE process) {
  std::wstring path(32768, L'\0');
  DWORD size = static_cast<DWORD>(path.size());
  if (!QueryFullProcessImageNameW(process, 0, path.data(), &size)) winFail("Cannot identify application process");
  path.resize(size);
  Handle image(CreateFileW(path.c_str(), FILE_READ_ATTRIBUTES,
      FILE_SHARE_READ | FILE_SHARE_WRITE | FILE_SHARE_DELETE, nullptr, OPEN_EXISTING, 0, nullptr));
  if (!image.valid()) winFail("Cannot resolve process image");
  return finalPath(image.get());
}
void waitForPid(DWORD pid, const fs::path& exe) {
  if (!pid) return;
  Handle process(OpenProcess(SYNCHRONIZE | PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid));
  if (!process.valid()) winFail("Supplied PID cannot be verified; retry without --pid after closing the app");
  if (!equal(processImage(process.get()), exe)) fail("PID does not belong to the target application.");
  log("Waiting for application exit (up to 60 seconds)...");
  if (WaitForSingleObject(process.get(), 60000) != WAIT_OBJECT_0) fail("Application did not exit; no files copied.");
}
void ensureAppStopped(const fs::path& exe) {
  Handle snapshot(CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0));
  if (!snapshot.valid()) winFail("Cannot enumerate processes");
  PROCESSENTRY32W entry{};
  entry.dwSize = sizeof(entry);
  if (!Process32FirstW(snapshot.get(), &entry)) winFail("Cannot inspect processes");
  do {
    if (!equal(fs::path(entry.szExeFile), fs::path(kExe))) continue;
    Handle process(OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, entry.th32ProcessID));
    if (!process.valid()) fail("Cannot verify a matching application process; close it before updating.");
    if (equal(processImage(process.get()), exe)) fail("Target application is still running.");
  } while (Process32NextW(snapshot.get(), &entry));
  if (GetLastError() != ERROR_NO_MORE_FILES) winFail("Process enumeration failed");
}
// Restart Manager is used only to detect users of existing program files.
// Never call RmShutdown or terminate any process.
void ensureFilesUnused(const std::vector<fs::path>& paths) {
  DWORD session = 0;
  wchar_t key[CCH_RM_SESSION_KEY + 1]{};
  if (RmStartSession(&session, 0, key) != ERROR_SUCCESS) fail("Cannot start file-use verification.");
  struct EndSession { DWORD id; ~EndSession() { RmEndSession(id); } } end{session};
  for (const auto& path : paths) {
    LPCWSTR name = path.c_str();
    if (RmRegisterResources(session, 1, &name, 0, nullptr, 0, nullptr) != ERROR_SUCCESS) fail("Cannot register files for use verification.");
  }
  UINT needed = 0, count = 0;
  DWORD reasons = 0;
  DWORD result = RmGetList(session, &needed, &count, nullptr, &reasons);
  if (result != ERROR_SUCCESS || needed != 0) fail("Application files are in use, or their use cannot be determined.");
}
struct CopyItem {
  fs::path destination;
  Handle source;
  Handle target;
};
int wmain(int argc, wchar_t* argv[]) {
  bool copyStarted = false;
  try {
    log("Local updater started.");
    fs::path app, source;
    DWORD pid = 0;
    bool exeSeen = false, pidSeen = false;
    for (int i = 1; i < argc; i += 2) {
      if (i + 1 >= argc) fail("Each option requires a value.");
      std::wstring key(argv[i]), value(argv[i + 1]);
      if (key == L"--app-dir" && app.empty()) app = value;
      else if (key == L"--source" && source.empty()) source = value;
      else if (key == L"--exe" && !exeSeen && value == kExe) exeSeen = true;
      else if (key == L"--pid" && !pidSeen) {
        if (value.empty() || value.find_first_not_of(L"0123456789") != std::wstring::npos) fail("PID must be a positive integer.");
        unsigned long long parsed = std::stoull(value);
        if (!parsed || parsed > MAXDWORD) fail("PID is out of range.");
        pid = static_cast<DWORD>(parsed);
        pidSeen = true;
      } else fail("Unknown/duplicate option or invalid executable name.");
    }
    if (app.empty() || source.empty() || !exeSeen) fail("Usage: holistic_local_updater --app-dir <absolute path> --source <absolute path> --exe holistic_anecdotal_records.exe [--pid <PID>]");
    app = normalized(app);
    source = normalized(source);
    rejectProtected(app);
    if (within(app, source) || within(source, app)) fail("Source and target must be separate, non-nested directories.");
    std::vector<Handle> pins;
    pinAncestors(app, pins);
    pinAncestors(source, pins);
    requireBundle(app);
    requireBundle(source);
    auto targetTree = inspectTree(app, pins);
    auto sourceTree = inspectTree(source, pins);
    // Run this executable from outside both trees; no self-update is supported.
    auto ownImage = processImage(GetCurrentProcess());
    if (within(ownImage, app) || within(ownImage, source)) fail("Run the updater from outside both bundle directories.");
    log("Validated application directory and staged source (including links and file types).");
    waitForPid(pid, app / kExe);
    ensureAppStopped(app / kExe);
    ensureFilesUnused(targetTree.files);
    std::vector<fs::path> createDirectories;
    for (const auto& path : sourceTree.directories) {
      auto dest = app / path.lexically_relative(source);
      if (fs::exists(dest)) {
        if (!fs::is_directory(dest)) fail("Staged directory conflicts with a target file.");
      } else createDirectories.push_back(dest);
    }
    std::vector<CopyItem> copies;
    for (const auto& path : sourceTree.files) {
      auto dest = app / path.lexically_relative(source);
      auto input = openChecked(path, false, GENERIC_READ, FILE_SHARE_READ);
      Handle output;
      if (fs::exists(dest)) output = openChecked(dest, false, GENERIC_READ | GENERIC_WRITE, FILE_SHARE_READ);
      copies.push_back({dest, std::move(input), std::move(output)});
    }
    // All inputs, collisions, existing destinations and process checks passed.
    // Retain every handle through completion; never reopen an existing target.
    ensureAppStopped(app / kExe);
    copyStarted = true;
    log("Copy started.");
    for (const auto& directory : createDirectories) {
      if (!CreateDirectoryW(directory.c_str(), nullptr)) winFail("Cannot create destination directory");
      pins.push_back(openChecked(directory, true, FILE_READ_ATTRIBUTES, FILE_SHARE_READ | FILE_SHARE_WRITE));
    }
    std::vector<char> buffer(1024 * 1024);
    for (auto& item : copies) {
      if (!item.target.valid()) {
        item.target = Handle(CreateFileW(item.destination.c_str(), GENERIC_READ | GENERIC_WRITE,
            FILE_SHARE_READ, nullptr, CREATE_NEW, FILE_ATTRIBUTE_NORMAL | FILE_FLAG_OPEN_REPARSE_POINT, nullptr));
        if (!item.target.valid()) winFail("Cannot create destination file safely");
      }
      DWORD read = 0;
      do {
        if (!ReadFile(item.source.get(), buffer.data(), static_cast<DWORD>(buffer.size()), &read, nullptr)) winFail("Cannot read staged file");
        DWORD offset = 0;
        while (offset < read) {
          DWORD written = 0;
          if (!WriteFile(item.target.get(), buffer.data() + offset, read - offset, &written, nullptr)) winFail("Cannot write destination file");
          if (!written) fail("Destination write made no progress.");
          offset += written;
        }
      } while (read);
      if (!SetEndOfFile(item.target.get()) || !FlushFileBuffers(item.target.get())) winFail("Cannot finish destination file");
    }
    log("Copy completed. Success. Restart the application manually.");
    return 0;
  } catch (const std::exception& error) {
    std::cerr << "Failure: " << error.what() << std::endl;
    if (copyStarted) std::cerr << "Replacement may be partial. Do not launch the app until the full bundle is restored or copied successfully. No rollback was performed." << std::endl;
    else std::cerr << "Validation/preflight failed; no application files were modified." << std::endl;
    return 1;
  }
}
