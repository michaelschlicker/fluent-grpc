import Vapor

extension Request {
    public var db: Database {
        self.db(nil)
    }

    public func db(_ id: DatabaseID?) -> Database {
        self.application.databases
            .database(id, logger: self.logger, on: self.eventLoop)!
    }
}

extension Application {
    public var db: Database {
        self.db(nil)
    }

    public func db(_ id: DatabaseID?) -> Database {
        self.databases
            .database(id, logger: self.logger, on: self.eventLoopGroup.next())!
    }

    public var databases: Databases {
        self.fluent.storage.databases
    }

    public var migrations: Migrations {
        self.fluent.storage.migrations
    }

    public var migrator: Migrator {
        Migrator(
            databases: self.databases,
            migrations: self.migrations,
            logger: self.logger,
            on: self.eventLoopGroup.next()
        )
    }

    public struct Fluent {
        final class Storage {
            let databases: Databases
            let migrations: Migrations

            init(threadPool: NIOThreadPool, on eventLoopGroup: EventLoopGroup) {
                self.databases = Databases(
                    threadPool: threadPool,
                    on: eventLoopGroup
                )
                self.migrations = .init()
            }
        }

        struct Key: StorageKey {
            typealias Value = Storage
        }

        struct Lifecycle: LifecycleHandler {
            func willBoot(_ application: Application) throws {
                struct Signature: CommandSignature {
                    @Flag(name: "auto-migrate", help: "If true, Fluent will automatically migrate your database on boot")
                    var autoMigrate: Bool

                    @Flag(name: "auto-revert", help: "If true, Fluent will automatically revert your database on boot")
                    var autoRevert: Bool

                    init() { }
                }

                let signature = try Signature(from: &application.environment.commandInput)
                if signature.autoRevert {
                    try application.migrator.setupIfNeeded().wait()
                    try application.migrator.revertAllBatches().wait()
                }
                if signature.autoMigrate {
                    try application.migrator.setupIfNeeded().wait()
                    try application.migrator.prepareBatch().wait()
                }
            }

            func shutdown(_ application: Application) {
                application.databases.shutdown()
            }
        }

        let application: Application

        var storage: Storage {
            if self.application.storage[Key.self] == nil {
                self.initialize()
            }
            return self.application.storage[Key.self]!
        }

        func initialize() {
            self.application.storage[Key.self] = .init(
                threadPool: self.application.threadPool,
                on: self.application.eventLoopGroup
            )
            self.application.lifecycle.use(Lifecycle())
            self.application.commands.use(MigrateCommand(), as: "migrate")
        }
    }

    public var fluent: Fluent {
        .init(application: self)
    }
}
