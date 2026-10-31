import Foundation
import Combine

/// SFTP 远程文件浏览器状态管理。分块流式下载,大文件不爆内存(参考 pockterm)。
@MainActor
final class SFTPBrowser: ObservableObject {
    let client: SFTPClient
    @Published var currentPath: String
    @Published var items: [SFTPFile] = []
    @Published var isLoading = false
    @Published var error: String?

    init(client: SFTPClient, initialPath: String = "/") {
        self.client = client
        self.currentPath = initialPath
    }

    func load() {
        isLoading = true
        error = nil
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            do {
                let list = try client.listDirectory(path: currentPath)
                let sorted = list.sorted {
                    if $0.isDirectory != $1.isDirectory { return $0.isDirectory }
                    return $0.name.localizedStandardCompare($1.name) == .orderedAscending
                }
                await MainActor.run {
                    self.items = sorted
                    self.isLoading = false
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    self.isLoading = false
                }
            }
        }
    }

    func enter(_ file: SFTPFile) {
        guard file.isDirectory else { return }
        let path = (currentPath == "/" ? "" : currentPath) + "/" + file.name
        currentPath = path
        load()
    }

    func up() {
        guard currentPath != "/" else { return }
        currentPath = (currentPath as NSString).deletingLastPathComponent
        if currentPath.isEmpty { currentPath = "/" }
        load()
    }

    func download(_ file: SFTPFile, to localURL: URL) {
        Task.detached(priority: .userInitiated) { [weak self] in
            let remote = (self?.currentPath == "/" ? "" : self?.currentPath ?? "") + "/" + file.name
            do {
                try self?.client.download(remotePath: remote, to: localURL)
            } catch {
                await MainActor.run { self?.error = error.localizedDescription }
            }
        }
    }

    func upload(_ url: URL) {
        let remote = (currentPath == "/" ? "" : currentPath) + "/" + url.lastPathComponent
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try self?.client.upload(localURL: url, to: remote)
                await MainActor.run { self?.load() }
            } catch {
                await MainActor.run { self?.error = error.localizedDescription }
            }
        }
    }

    func createDir(_ name: String) {
        let path = (currentPath == "/" ? "" : currentPath) + "/" + name
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try self?.client.createDirectory(path: path)
                await MainActor.run { self?.load() }
            } catch {
                await MainActor.run { self?.error = error.localizedDescription }
            }
        }
    }

    func delete(_ file: SFTPFile) {
        let path = (currentPath == "/" ? "" : currentPath) + "/" + file.name
        Task.detached(priority: .userInitiated) { [weak self] in
            do {
                try self?.client.remove(path: path)
                await MainActor.run { self?.load() }
            } catch {
                await MainActor.run { self?.error = error.localizedDescription }
            }
        }
    }
}
