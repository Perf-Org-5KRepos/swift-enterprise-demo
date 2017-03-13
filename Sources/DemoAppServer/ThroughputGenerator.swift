/**
 * Copyright IBM Corporation 2017
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 * http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 **/

import Foundation
import LoggerAPI
import Configuration
import CloudFoundryEnv
#if os(Linux)
    import Dispatch
#endif

class ThroughputGenerator {
    var queue: DispatchQueue
    var requestsPerSecond: Int
    var workItem: DispatchWorkItem?

    init() {
        self.queue = DispatchQueue(label: "throughputQueue", qos: DispatchQoS.background)
        self.requestsPerSecond = 0
        self.workItem = nil
    }

    func generateThroughputWithWhile(configMgr: ConfigurationManager, requestsPerSecond: Int, vcapCookie: String?) {
        // Set the field.
        self.requestsPerSecond = requestsPerSecond
        
        // Cancel previous work items.
        self.workItem?.cancel()

        // If requestsPerSecond is 0 or less, don't bother creating new threads.
        guard requestsPerSecond > 0 else {
            return
        }

        var requestURL = "http://localhost:8080/requestJSON"
        if configMgr.isLocal == false {
            requestURL = "\(configMgr.url)/requestJSON"
        }
        
        self.workItem = DispatchWorkItem() {
            let workerQueue = DispatchQueue(label: "throughputWorkerQueue", qos: DispatchQoS.background, attributes: .concurrent)
            guard let selfReference = self.workItem else {
                Log.warning("Worker thread lost reference to work item and will self-destruct.")
                return
            }
            let deadline: DispatchTime = DispatchTime.now() + DispatchTimeInterval.seconds(1)
            
            // Make a request, don't worry about the result.
            if let requestURL = URL(string: requestURL) {
                // Set cookies in order to ensure session affinity.
                var cookies: [String: Any] = [:]
                if configMgr.isLocal == false, let appData = configMgr.getApp(), let vcap = vcapCookie {
                    cookies["JSESSIONID"] = "\(appData.instanceIndex)"
                    cookies["__VCAP_ID__"] = vcap
                }
                for _ in 0..<requestsPerSecond {
                    workerQueue.async(execute: {
                        networkRequest(url: requestURL, method: "GET", cookies: cookies) {
                            data, response, error in
                            return
                        }
                    })
                }
            }
            
            if !selfReference.isCancelled, let workItem = self.workItem {
                self.queue.asyncAfter(deadline: deadline, execute: workItem)
            }
        }
        
        if let workItem = self.workItem {
            self.queue.async(execute: workItem)
        }
    }
}
