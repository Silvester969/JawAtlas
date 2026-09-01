import Foundation

public enum BundleConverter {
    public static func convert(
        candidate: SeriesCandidate,
        label: String,
        caseID: UUID = UUID(),
        casesDirectory: URL,
        importedAt: Date = Date(),
        progress: @Sendable (ImportProgress) -> Void = { _ in }
    ) throws -> CaseRecord {
        let identifier = caseID.uuidString
        let directory = casesDirectory.appendingPathComponent(identifier, isDirectory: true)
        do {
            let record = try performConversion(
                candidate: candidate,
                label: label,
                identifier: identifier,
                directory: directory,
                casesDirectory: casesDirectory,
                importedAt: importedAt,
                progress: progress
            )
            return record
        } catch {
            try? FileManager.default.removeItem(at: directory)
            throw error
        }
    }

    private static func performConversion(
        candidate: SeriesCandidate,
        label: String,
        identifier: String,
        directory: URL,
        casesDirectory: URL,
        importedAt: Date,
        progress: @Sendable (ImportProgress) -> Void
    ) throws -> CaseRecord {
        let manager = FileManager.default
        try manager.createDirectory(at: casesDirectory, withIntermediateDirectories: true)
        try ensureFreeSpace(for: candidate.volumeByteCount, at: casesDirectory)
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)

        let partialURL = BundleLayout.volumeURL(in: directory)
            .appendingPathExtension(String(BundleLayout.partialSuffix.dropFirst()))
        manager.createFile(atPath: partialURL.path, contents: nil)
        guard let writer = try? FileHandle(forWritingTo: partialURL) else {
            throw ImportError.writeFailed("could not open the scan file")
        }

        let width = candidate.columns
        let height = candidate.rows
        let perSlice = width * height
        let middleIndex = candidate.slices.count / 2
        var middleSlice: [Int16] = []
        var hasher = StreamingHasher()
        var buffer = [Int16](repeating: 0, count: perSlice)
        var denyValues = Set<String>()
        let calibrationOffset = estimateCalibrationOffset(candidate: candidate, buffer: &buffer)

        progress(ImportProgress(phase: .converting, completed: 0, total: candidate.slices.count))

        do {
            for (index, slice) in candidate.slices.enumerated() {
                try Task.checkCancellation()
                for value in slice.identifierValues { denyValues.insert(value) }
                try PixelDecoder.decodeFrame(
                    fileAt: slice.sourceURL,
                    slice: slice,
                    calibrationOffset: calibrationOffset,
                    into: &buffer
                )
                try buffer.withUnsafeBufferPointer { pointer in
                    let bytes = UnsafeRawBufferPointer(pointer)
                    hasher.update(bytes)
                    try writer.write(contentsOf: Data(bytes))
                }
                if index == middleIndex { middleSlice = buffer }
                if index % 32 == 31 { try writer.synchronize() }
                progress(ImportProgress(phase: .converting, completed: index + 1, total: candidate.slices.count))
            }
            try writer.synchronize()
            try writer.close()
        } catch is CancellationError {
            try? writer.close()
            throw ImportError.cancelled
        } catch let error as DICOMError {
            try? writer.close()
            throw ImportError.inconsistentGeometry(describe(error))
        } catch {
            try? writer.close()
            throw diskAwareError(error)
        }

        try manager.moveItem(at: partialURL, to: BundleLayout.volumeURL(in: directory))

        progress(ImportProgress(phase: .verifying, completed: 0, total: 3))

        if !middleSlice.isEmpty {
            let png = middleSlice.withUnsafeBufferPointer { pointer in
                SliceImageRenderer.thumbnailPNG(from: pointer, width: width, height: height)
            }
            if let png {
                try? png.write(to: BundleLayout.thumbnailURL(in: directory), options: [.atomic])
            }
        }
        progress(ImportProgress(phase: .verifying, completed: 1, total: 3))

        let manifest = BundleManifest(
            caseID: identifier,
            label: label,
            importedAt: importedAt,
            dimensions: [width, height, candidate.slices.count],
            spacingMM: [candidate.spacingMM.x, candidate.spacingMM.y, candidate.spacingMM.z],
            orientation: orientationMatrix(for: candidate),
            originMM: [candidate.origin.x, candidate.origin.y, candidate.origin.z],
            volumeSHA256: hasher.finalizedHex(),
            isGapped: candidate.isGapped,
            seriesUIDHash: candidate.seriesUIDHash
        )
        let manifestData = try BundleManifest.encoder().encode(manifest)

        if let hit = IntegrityVerifier.denyListHit(in: manifestData, denyValues: Array(denyValues)) {
            throw ImportError.identifierLeak(hit)
        }
        progress(ImportProgress(phase: .verifying, completed: 2, total: 3))

        do {
            try manifestData.write(to: BundleLayout.manifestURL(in: directory), options: [.atomic])
        } catch {
            throw diskAwareError(error)
        }

        try IntegrityVerifier.quickCheck(manifest: manifest, directory: directory)
        applyFileProtection(in: directory)
        progress(ImportProgress(phase: .verifying, completed: 3, total: 3))

        return CaseRecord(
            id: identifier,
            label: label,
            importedAt: importedAt,
            dimensions: manifest.dimensions,
            spacingMM: manifest.spacingMM,
            isGapped: manifest.isGapped,
            seriesUIDHash: manifest.seriesUIDHash,
            patientTag: nil,
            volumeByteCount: manifest.volumeByteCount,
            storageByteCount: Int64(manifest.volumeByteCount),
            directory: directory,
            status: .ready
        )
    }

    static func estimateCalibrationOffset(candidate: SeriesCandidate, buffer: inout [Int16]) -> Double {
        guard let probe = candidate.slices.first, !probe.hasRescaleTags else { return 0 }
        let middle = candidate.slices[candidate.slices.count / 2]
        guard (try? PixelDecoder.decodeFrame(fileAt: middle.sourceURL, slice: middle, into: &buffer)) != nil else {
            return 0
        }
        let width = candidate.columns
        let height = candidate.rows
        let block = 8
        var total = 0.0
        var count = 0.0
        for cornerY in [0, height - block] {
            for cornerX in [0, width - block] {
                for y in cornerY..<(cornerY + block) {
                    for x in cornerX..<(cornerX + block) {
                        total += Double(buffer[y * width + x])
                        count += 1
                    }
                }
            }
        }
        guard count > 0 else { return 0 }
        let airEstimate = total / count
        let offset = -1000 - airEstimate
        guard abs(offset) > 150, abs(offset) < 4100 else { return 0 }
        return offset
    }

    static func applyFileProtection(in directory: URL) {
        let manager = FileManager.default
        let attributes: [FileAttributeKey: Any] = [
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ]
        try? manager.setAttributes(attributes, ofItemAtPath: directory.path)
        let contents = (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)) ?? []
        for file in contents {
            try? manager.setAttributes(attributes, ofItemAtPath: file.path)
        }
    }

    public static func orientationMatrix(for candidate: SeriesCandidate) -> [[Float]] {
        let rows = [candidate.rowDirection, candidate.columnDirection, candidate.sliceNormal]
        return rows.map { [Float($0.x), Float($0.y), Float($0.z), 0] }
    }

    private static func ensureFreeSpace(for byteCount: Int, at url: URL) throws {
        let required = Int64(Double(byteCount) * 1.2) + (8 << 20)
        guard let values = try? url.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey]),
              let available = values.volumeAvailableCapacityForImportantUsage else {
            return
        }
        guard available > required else { throw ImportError.diskFull }
    }

    private static func diskAwareError(_ error: Error) -> ImportError {
        let code = (error as NSError).code
        if code == NSFileWriteOutOfSpaceError || code == Int(ENOSPC) { return .diskFull }
        return .writeFailed("the scan could not be written to storage")
    }

    private static func describe(_ error: DICOMError) -> String {
        switch error {
        case .truncated: return "a slice ended unexpectedly"
        case .notDICOM: return "a file is not a DICOM slice"
        case .fileTooLarge: return "a file is too large to read"
        case let .unsupportedTransferSyntax(uid): return "compressed slices are not supported (\(uid))"
        case let .unsupportedPixelFormat(detail): return "unsupported pixel format (\(detail))"
        case let .missingRequiredTag(tag): return "a slice is missing \(tag)"
        case let .malformedValue(field): return "a slice has an invalid \(field)"
        case let .unsupportedStructure(detail): return "unsupported file structure (\(detail))"
        }
    }
}
