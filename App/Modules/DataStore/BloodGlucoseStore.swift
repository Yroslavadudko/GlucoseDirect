//
//  BloodGlucoseStore.swift
//  GlucoseDirectApp
//
//  https://github.com/groue/GRDB.swift
//

import Combine
import Foundation
import GRDB

func bloodGlucoseStoreMiddleware() -> Middleware<DirectState, DirectAction> {
    return { state, action, _ in
        switch action {
        case .startup:
            DataStore.shared.createBloodGlucoseTable()

        case .addBloodGlucose(glucoseValues: let glucoseValues):
            guard !glucoseValues.isEmpty else {
                break
            }

            DataStore.shared.insertBloodGlucose(glucoseValues)

            return Just(DirectAction.loadBloodGlucoseValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .deleteBloodGlucose(glucose: let glucose):
            DataStore.shared.deleteBloodGlucose(glucose)

            return Just(DirectAction.loadBloodGlucoseValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .clearBloodGlucoseValues:
            DataStore.shared.deleteAllBloodGlucose()

            return Just(DirectAction.loadBloodGlucoseValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        case .loadBloodGlucoseValues:
            guard state.appState == .active else {
                break
            }

            return DataStore.shared.getBloodGlucoseValues().map { glucoseValues in
                DirectAction.setBloodGlucoseValues(glucoseValues: glucoseValues)
            }.eraseToAnyPublisher()

        case .setAppState(appState: let appState):
            guard appState == .active else {
                break
            }

            return Just(DirectAction.loadBloodGlucoseValues)
                .setFailureType(to: DirectError.self)
                .eraseToAnyPublisher()

        default:
            break
        }

        return Empty().eraseToAnyPublisher()
    }
}

private extension DataStore {
    func createBloodGlucoseTable() {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    try db.create(table: BloodGlucose.Table, ifNotExists: true) { t in
                        t.column(BloodGlucose.Columns.id.name, .text)
                            .primaryKey()
                        t.column(BloodGlucose.Columns.timestamp.name, .date)
                            .notNull()
                            .indexed()
                        t.column(BloodGlucose.Columns.glucoseValue.name, .integer)
                            .notNull()
                        t.column(BloodGlucose.Columns.timegroup.name, .date)
                            .notNull()
                            .indexed()
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func deleteAllBloodGlucose() {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    do {
                        try BloodGlucose.deleteAll(db)
                    } catch {
                        DirectLog.error("\(error)")
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func deleteBloodGlucose(_ value: BloodGlucose) {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    do {
                        try BloodGlucose.deleteOne(db, id: value.id)
                    } catch {
                        DirectLog.error("\(error)")
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func insertBloodGlucose(_ values: [BloodGlucose]) {
        if let dbQueue = dbQueue {
            do {
                try dbQueue.write { db in
                    values.forEach { value in
                        do {
                            try value.insert(db)
                        } catch {
                            DirectLog.error("\(error)")
                        }
                    }
                }
            } catch {
                DirectLog.error("\(error)")
            }
        }
    }

    func getBloodGlucoseValues(upToDay: Int? = 1) -> Future<[BloodGlucose], DirectError> {
        return Future { promise in
            if let dbQueue = self.dbQueue {
                dbQueue.asyncRead { asyncDB in
                    do {
                        if let upToDay = upToDay,
                           let upTo = Calendar.current.date(byAdding: .day, value: -upToDay, to: Date())
                        {
                            let db = try asyncDB.get()
                            let result = try BloodGlucose
                                .filter(Column(BloodGlucose.Columns.timestamp.name) > upTo)
                                .order(Column(BloodGlucose.Columns.timestamp.name))
                                .fetchAll(db)

                            promise(.success(result))
                        } else {
                            let db = try asyncDB.get()
                            let result = try BloodGlucose
                                .order(Column(BloodGlucose.Columns.timestamp.name))
                                .fetchAll(db)

                            promise(.success(result))
                        }
                    } catch {
                        promise(.failure(.withMessage(error.localizedDescription)))
                    }
                }
            }
        }
    }

    func getBloodGlucoseHistory(fromDay: Int = 1, upToDay: Int = 7) -> Future<[BloodGlucose], DirectError> {
        return Future { promise in
            if let dbQueue = self.dbQueue {
                dbQueue.asyncRead { asyncDB in
                    do {
                        if let from = Calendar.current.date(byAdding: .day, value: -fromDay, to: Date()),
                           let upTo = Calendar.current.date(byAdding: .day, value: -upToDay, to: Date())
                        {
                            let db = try asyncDB.get()
                            let result = try BloodGlucose
                                .filter(Column(BloodGlucose.Columns.timestamp.name) <= from)
                                .filter(Column(BloodGlucose.Columns.timestamp.name) > upTo)
                                .select(
                                    min(BloodGlucose.Columns.id).forKey(BloodGlucose.Columns.id.name),
                                    BloodGlucose.Columns.timegroup.forKey(BloodGlucose.Columns.timestamp.name),
                                    average(BloodGlucose.Columns.glucoseValue).forKey(BloodGlucose.Columns.glucoseValue.name),
                                    BloodGlucose.Columns.timegroup
                                )
                                .group(BloodGlucose.Columns.timegroup)
                                .order(Column(BloodGlucose.Columns.timestamp.name))
                                .fetchAll(db)

                            promise(.success(result))
                        } else {
                            promise(.failure(.withMessage("Cannot get calendar dates")))
                        }
                    } catch {
                        promise(.failure(.withMessage(error.localizedDescription)))
                    }
                }
            }
        }
    }
}
