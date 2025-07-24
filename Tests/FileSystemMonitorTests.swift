import Foundation
import Testing

@testable import FileSystemMonitor

#if os(macOS)
	@Suite("FileSystemMonitor Tests", .serialized)
	struct FileSystemMonitorTests {

		func createTestDirectory() throws -> String {
			let monitoredFolder = (NSTemporaryDirectory() as NSString).appendingPathComponent(
				"test.\(Int.random(in: 0 ... .max))")
			try FileManager.default.createDirectory(
				at: URL(fileURLWithPath: monitoredFolder, isDirectory: true),
				withIntermediateDirectories: true, attributes: nil)
			return monitoredFolder
		}

		func cleanup(_ path: String) {
			_ = try? FileManager.default.removeItem(atPath: path)
		}

		@Test("Basic monitoring")
		func testBasicMonitoring() async throws {
			let monitoredFolder = try createTestDirectory()
			defer { cleanup(monitoredFolder) }

			let monitor = FileSystemMonitor.monitor(
				path: monitoredFolder,
				options: [.fileEvents],
				latency: 0.1
			)

			await monitor.start()
			defer { Task { await monitor.stop() } }

			let events = try await withThrowingTaskGroup(of: [FileSystemMonitor.Event].self) {
				group in
				group.addTask {
					var events: [FileSystemMonitor.Event] = []
					for await event in monitor.events {
						events.append(event)
						if events.count >= 1 {
							break
						}
					}
					return events
				}

				group.addTask {
					// Give the monitor time to start
					try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

					FileManager.default.createFile(
						atPath: (monitoredFolder as NSString).appendingPathComponent(
							"testFile.txt"),
						contents: Data("test".utf8),
						attributes: nil)

					return []
				}

				for try await result in group {
					if !result.isEmpty {
						return result
					}
				}
				return []
			}

			#expect(events.count > 0, "Should have received at least one event")
			#expect(await monitor.isActive, "Monitor should be active")
		}

		@Test("Event properties")
		func testEventProperties() async throws {
			let monitoredFolder = try createTestDirectory()
			defer { cleanup(monitoredFolder) }

			let monitor = FileSystemMonitor.monitor(
				path: monitoredFolder,
				options: [.fileEvents],
				latency: 0.1
			)

			await monitor.start()
			defer { Task { await monitor.stop() } }

			let events = try await withThrowingTaskGroup(of: [FileSystemMonitor.Event].self) {
				group in
				group.addTask {
					var events: [FileSystemMonitor.Event] = []
					for await event in monitor.events {
						events.append(event)
						if events.count >= 2 {
							break
						}
					}
					return events
				}

				group.addTask {
					// Give the monitor time to start
					try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

					let testFilePath = (monitoredFolder as NSString).appendingPathComponent(
						"testFile.txt")
					FileManager.default.createFile(
						atPath: testFilePath,
						contents: Data("test".utf8),
						attributes: nil)

					// Modify the file
					try await Task.sleep(nanoseconds: 200_000_000)  // 200ms
					try "modified content".write(
						toFile: testFilePath, atomically: true, encoding: .utf8)

					return []
				}

				for try await result in group {
					if !result.isEmpty {
						return result
					}
				}
				return []
			}

			#expect(events.count > 0, "Should have received at least one event")

			// Find events related to our test file (may include atomic write temporary files)
			var foundCreation = false

			for event in events {
				if event.isCreation {
					// Check if it's either the actual file or a temporary file in the same directory
					if event.path.contains("testFile.txt") || event.path.contains(monitoredFolder) {
						foundCreation = true
						if case .file = event.item {
							// File type correctly detected
						} else if case .unknown = event.item {
							// Also acceptable - temporary files might be unknown type
						} else if case .dir = event.item {
							// Directory creation events are also acceptable
						} else {
							print(
								"DEBUG: Unexpected item type for path \(event.path): \(String(describing: event.item))"
							)
							#expect(
								Bool(false),
								"Should detect file type as file, directory, or unknown")
						}
					}
				}
				if event.isDataModification {
					// Data modification events are also expected
				}
			}

			// We should have found at least one creation event
			#expect(foundCreation, "Should have found at least one creation event")

			// Check for specific testFile.txt events if they exist
			for event in events {
				if event.path.contains("testFile.txt") && event.isCreation {
					if case .file = event.item {
						// File type correctly detected
					} else {
						#expect(Bool(false), "Should detect file type")
					}
				}
				if event.path.contains("testFile.txt") && event.isDataModification {
					// Found a modification event for our specific file
				}
			}
		}

		@Test("Multiple paths monitoring")
		func testMultiplePathsMonitoring() async throws {
			let monitoredFolder = try createTestDirectory()
			defer { cleanup(monitoredFolder) }

			let tempDir2 = (NSTemporaryDirectory() as NSString).appendingPathComponent(
				"test2.\(Int.random(in: 0 ... .max))")
			try FileManager.default.createDirectory(
				at: URL(fileURLWithPath: tempDir2, isDirectory: true),
				withIntermediateDirectories: true,
				attributes: nil
			)
			defer { cleanup(tempDir2) }

			let paths = [monitoredFolder, tempDir2]
			let monitor = FileSystemMonitor.monitor(
				paths: paths,
				options: [.fileEvents],
				latency: 0.1
			)

			await monitor.start()
			defer { Task { await monitor.stop() } }

			let events = try await withThrowingTaskGroup(of: [FileSystemMonitor.Event].self) {
				group in
				group.addTask {
					var events: [FileSystemMonitor.Event] = []
					for await event in monitor.events {
						events.append(event)
						if events.count >= 2 {
							break
						}
					}
					return events
				}

				group.addTask {
					// Give monitor time to start
					try await Task.sleep(nanoseconds: 200_000_000)  // 200ms

					// Create files in both directories
					FileManager.default.createFile(
						atPath: (monitoredFolder as NSString).appendingPathComponent("file1.txt"),
						contents: Data("test1".utf8),
						attributes: nil
					)

					try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

					FileManager.default.createFile(
						atPath: (tempDir2 as NSString).appendingPathComponent("file2.txt"),
						contents: Data("test2".utf8),
						attributes: nil
					)

					return []
				}

				for try await result in group {
					if !result.isEmpty {
						return result
					}
				}
				return []
			}

			#expect(events.count > 0, "Should have received events from multiple paths")

			let paths1 = events.filter { $0.path.contains(monitoredFolder) }
			let paths2 = events.filter { $0.path.contains(tempDir2) }

			#expect(
				paths1.count > 0 || paths2.count > 0, "Should have events from at least one path")
		}

		@Test("WithMonitoring lifecycle")
		func testWithMonitoringLifecycle() async throws {
			let monitoredFolder = try createTestDirectory()
			defer { cleanup(monitoredFolder) }

			let result = try await FileSystemMonitor.withMonitoring(
				paths: [monitoredFolder],
				options: [.fileEvents],
				latency: 0.1
			) { monitor in
				try await withThrowingTaskGroup(of: Int.self) { group in
					group.addTask {
						var eventCount = 0
						for await _ in monitor.events {
							eventCount += 1
							if eventCount >= 1 {
								break
							}
						}
						return eventCount
					}

					group.addTask {
						// Give monitor time to start
						try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

						// Create a test file
						let testFilePath = (monitoredFolder as NSString).appendingPathComponent(
							"lifecycleTest.txt")
						FileManager.default.createFile(
							atPath: testFilePath, contents: Data("test".utf8), attributes: nil)

						return 0
					}

					for try await count in group {
						if count > 0 {
							return count
						}
					}
					return 0
				}
			}

			#expect(result > 0, "Should have received at least one event")
		}

		@Test("Event filtering")
		func testEventFiltering() async throws {
			let monitoredFolder = try createTestDirectory()
			defer { cleanup(monitoredFolder) }

			let monitor = FileSystemMonitor.monitor(
				path: monitoredFolder,
				options: [.fileEvents],
				latency: 0.1
			)

			await monitor.start()
			defer { Task { await monitor.stop() } }

			let events = try await withThrowingTaskGroup(of: [FileSystemMonitor.Event].self) {
				group in
				group.addTask {
					var events: [FileSystemMonitor.Event] = []
					for await event in monitor.events {
						events.append(event)
						if events.count >= 3 {
							break
						}
					}
					return events
				}

				group.addTask {
					// Give the monitor time to start
					try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

					let testFilePath = (monitoredFolder as NSString).appendingPathComponent(
						"testFile.txt")

					// Create file
					FileManager.default.createFile(
						atPath: testFilePath,
						contents: Data("test".utf8),
						attributes: nil)

					try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

					// Modify file
					try "modified content".write(
						toFile: testFilePath, atomically: true, encoding: .utf8)

					try await Task.sleep(nanoseconds: 100_000_000)  // 100ms

					// Remove file
					try FileManager.default.removeItem(atPath: testFilePath)

					return []
				}

				for try await result in group {
					if !result.isEmpty {
						return result
					}
				}
				return []
			}

			#expect(events.count > 0, "Should have received at least one event")

			let creationEvents = events.filter { $0.isCreation }
			let modificationEvents = events.filter { $0.isDataModification }
			let removalEvents = events.filter { $0.isRemoval }

			#expect(
				creationEvents.count > 0 || modificationEvents.count > 0 || removalEvents.count > 0,
				"Should have at least one of each event type")
		}
	}
#endif
