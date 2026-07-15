//
//  ContactPhotoCache.swift
//  llama Mail
//
//  Disk cache for contact photo bytes, keyed by the server's photoRef.
//  photoRef filenames are content-hashed server-side, so an entry is
//  immutable — nothing is ever invalidated, new refs just add new files
//  (Client_Contact_Update.md Part 3).
//

import Foundation

final class ContactPhotoCache: Sendable {
    private let directory: URL

    /// - Parameter directory: override for tests; defaults to
    ///   Application Support/ContactPhotos.
    init(directory: URL? = nil) {
        self.directory = directory ?? FileManager.default
            .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appending(path: "ContactPhotos", directoryHint: .isDirectory)
    }

    func data(for photoRef: String) -> Data? {
        guard let url = fileURL(for: photoRef) else { return nil }
        return try? Data(contentsOf: url)
    }

    func hasData(for photoRef: String) -> Bool {
        guard let url = fileURL(for: photoRef) else { return false }
        return FileManager.default.fileExists(atPath: url.path)
    }

    func store(_ data: Data, for photoRef: String) {
        guard let url = fileURL(for: photoRef) else { return }
        try? FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        try? data.write(to: url, options: .atomic)
    }

    /// photoRef is a server-generated "<sha256>.<ext>" filename, but never
    /// trust it as a path: anything that isn't a plain filename is rejected.
    private func fileURL(for photoRef: String) -> URL? {
        guard !photoRef.isEmpty,
              !photoRef.contains("/"),
              !photoRef.contains("..")
        else { return nil }
        return directory.appending(path: photoRef, directoryHint: .notDirectory)
    }
}
