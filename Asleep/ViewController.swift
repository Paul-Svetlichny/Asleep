//
//  ViewController.swift
//  Asleep
//
//  Created by Paul Svetlichny on 01.11.2020.
//

/*  Sleep data analysis algorithm description
 *
 *  1. Query for sleep records from HealthKit
 *  2. Get all uniques dates based on sleep record end date (regardless of record category value) - (complexity is O(n))
 *  3. Loop through all sleep records for each unique date and sum the amount of sleep time for a period between start date and end date in seconds.
 *  As we don't know the initial definition for a "day", it is assumed that all sleep periods, ending at the current date, are counted as "amount of sleep per day"
 *  For example:
 *  ===
 *  05/11 10:30 PM - 06/11 06:15 AM (sleeping during the night)
 *  06/11 02:00 PM - 03:00 PM (Hola, siesta!)
 *  06/11 10:15 PM - 07/11 06:15 AM (sleeping during the night)
 *  ===
 *  In the example given, there will be two records generated:
 *  06/11 Total sleep time: 8 hours 45 minutes (night sleep + siesta)
 *  07/11 Total sleep time: 8 hours (only sleep time)
 *
 *  Caveats:
 *  Time in bed is not taken into account, meaning that a sleep period with awakening before midnight will be counted as amount of sleep time for the previous day
 *  E.g.
 *  ===
 *  05/11 10:30 PM - 11:45 PM (awaken but still in bed)
 *  05/11 11:50 PM - 06/11 6:15 AM (sleep time)
 *  ===
 *  Will generate two records:
 *  05/11 Total sleep time: 1 hours 15 minutes
 *  06/11 Total sleep time: 6 hours 25 minutes
 *  Which is technically correct, but may not be what the user wants to see. This is not implemented due to the time limit. The more complex logic should be applied to also
 *  count cases, where user wakes up during the night to go get some water or have a night snack.
 *
 */


import UIKit
import HealthKit

class ViewController: UIViewController {

    private let sleepAnalysisSamplesLimit = 30
    private let healthStore = HKHealthStore()
    
    override func viewDidLoad() {
        super.viewDidLoad()

        requestHealthKitAuthorization { [weak self] result in
            guard let self = self else {
                return
            }
            
            switch result {
            case .success(let success):
                if success {
//                    Uncomment to write initial data.
//                    Consecutive writes will APPEND data, NOT OVERRIDE it. This will lead to different sleep periods overlaping,
//                    which should not be possible during a routine sleep tracker usage
//                    self.recordInitialSleepData()
                    
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                        self.retrieveSleepAnalysis()
                    }
                } else {
                    NotificationPresenter.show(.alert, in: self, title: "Requesting Authorization", message: "Requesting authorization denied", actions: nil)
                }
            case .failure(let error):
                NotificationPresenter.show(.alert, in: self, title: "Error Requesting Authorization", message: error.localizedDescription, actions: nil)
            }
        }
    }

    private func requestHealthKitAuthorization(result: @escaping (Result<Bool, Error>) -> Void) {
        guard let sleepAnalysisCategoryType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            result(.failure(NSError(domain: "HealthKitAuthorizationDomain", code: 0, userInfo: [NSLocalizedDescriptionKey: "Error defining sleep analysis category"])))
            return
        }
        
        let typesToRead = Set([sleepAnalysisCategoryType])
        let typesToShare = Set([sleepAnalysisCategoryType])
        
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { (success, error) -> Void in
            if let error = error {
                result(.failure(error))
                return
            }

            result(.success(success))
        }
    }
    
    private func retrieveSleepAnalysis() {
        guard let sleepAnalysisCategoryType = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else {
            NotificationPresenter.show(.alert, in: self, title: "Error Requesting Authorization", message: "Error defining sleep analysis category", actions: nil)
            return
        }

        let sortDescriptor = NSSortDescriptor(key: HKSampleSortIdentifierEndDate, ascending: false)
        let sleepDataQuery = HKSampleQuery(sampleType: sleepAnalysisCategoryType, predicate: nil, limit: sleepAnalysisSamplesLimit, sortDescriptors: [sortDescriptor]) { (query, result, error) -> Void in
            if error != nil {
                NotificationPresenter.show(.alert, in: self, title: "Error Querying Sleep Data", message: error?.localizedDescription, actions: nil)
                return
            }

            guard let categories = result else {
                return
            }
            
            let uniqueDates: [Date] = Array(Set(categories.compactMap { category in
                let endDate = category.endDate
                let calendar = Calendar.current
                let dateComponents = calendar.dateComponents([.year, .month, .day], from: endDate)

                return calendar.date(from: dateComponents)
            }))
            
            guard let sleepSamples = result?.compactMap({ $0 as? HKCategorySample }) else {
                NotificationPresenter.show(.alert, in: self, title: nil, message: "No sleep records available", actions: nil)
                return
            }
            
            var sleepTimeByDays = [Date: Int]()
            uniqueDates.forEach { day in
                var sleepTime = 0
                sleepSamples.forEach { category in
                    if category.value == HKCategoryValueSleepAnalysis.asleep.rawValue {
                        if Calendar.current.isDate(category.endDate, inSameDayAs: day) {
                            let dateComponents = Calendar.current.dateComponents(Set<Calendar.Component>([ .second]), from: category.startDate, to: category.endDate)
                            let seconds = dateComponents.second
                            sleepTime += seconds ?? 0
                        }
                    }
                }
                sleepTimeByDays[day] = sleepTime
            }
            
            let dateFormatter = DateFormatter()
            dateFormatter.timeZone = TimeZone.current
            dateFormatter.dateFormat = "dd MMM yyyy"
            
            for (date, time) in sleepTimeByDays.sorted(by: { $0 < $1 }) {
                let hours = time / 3600
                let minutes = time / 60 - hours * 60
                let seconds = time - hours * 3600 - minutes * 60
                                    
                print("Sleep time on \(dateFormatter.string(from: date)) is: \(String(format: "%02d", hours)):\(String(format: "%02d", minutes)):\(String(format: "%02d", seconds))")
            }
        }
        
        healthStore.execute(sleepDataQuery)
    }
    
    private func recordInitialSleepData() {
        let now = Date()
        let calendar = Calendar.current
        
        for i in 0...10 {
//            Random time values for sleep data generation
            let randomOffsetTime = Int.random(in: 0..<24)                   //  Time offset from current date to set start sleep time in hours
            let randomSleepTime = Int.random(in: 5 * 3600 ..< 10 * 3600)    //  Sleep time in seconds to get more realistic results from 5 to 10 hours
            let randomStartSleepOffset = Int.random(in: 5..<15)             //  The offset in minutes to get asleep (from 5 to 15 minutes)
            let randomEndSleepOffset = Int.random(in: 0..<5)                //  The offset in minutes to get up from bed after awaking

            guard
                let startInBedDate = calendar.date(byAdding: .hour, value: -randomOffsetTime - (i * 24), to: now),
                let startSleepDate = calendar.date(byAdding: .minute, value: randomStartSleepOffset, to: startInBedDate),
                let endSleepDate = calendar.date(byAdding: .second, value: randomSleepTime, to: startSleepDate),
                let endInBedDate = calendar.date(byAdding: .minute, value: randomEndSleepOffset, to: endSleepDate),
                let sleepType = HKObjectType.categoryType(forIdentifier: HKCategoryTypeIdentifier.sleepAnalysis)
            else {
                return
            }
            
            let inBed = HKCategorySample.init(type: sleepType, value: HKCategoryValueSleepAnalysis.inBed.rawValue, start: startInBedDate, end: endInBedDate)
            let asleep = HKCategorySample.init(type: sleepType, value: HKCategoryValueSleepAnalysis.asleep.rawValue, start: startSleepDate, end: endSleepDate)
            
            healthStore.save([inBed, asleep]) { (success, error) in
                if let error = error {
                    NotificationPresenter.show(.alert, in: self, title: "Error Saving Data", message: error.localizedDescription, actions: nil)
                }
            }
        }
    }
}

