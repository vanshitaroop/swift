// RUN: %target-run-simple-swift( -Xfrontend -disable-availability-checking %import-libdispatch -parse-as-library)

// REQUIRES: executable_test
// REQUIRES: concurrency
// REQUIRES: libdispatch

// rdar://76038845
// REQUIRES: concurrency_runtime
// UNSUPPORTED: back_deployment_runtime

import StdlibUnittest
import Darwin
import Dispatch

func loopUntil(priority: TaskPriority) async {
  while (Task.currentPriority != priority) {
    await Task.sleep(1_000_000_000)
  }
}

func getNestedTaskPriority() async -> (TaskPriority, TaskPriority) {
  return (Task.basePriority!, Task.currentPriority)
}

@main struct Main {
  static func main() async {

    let tests = TestSuite("Task base priority")
    if #available(SwiftStdlib 5.1, *) {

      tests.test("Structured concurrency base priority propagation") {
        Task(priority: .background) {
          await loopUntil(priority: .default)

          let basePri = Task.basePriority!
          let curPri = Task.currentPriority
          expectEqual(basePri, .background)
          expectEqual(curPri, .default)

          // Structured concurrency via async let, escalated priority should
          // propagate
          async let (nestedBasePri, nestedCurPri) = getNestedTaskPriority()
          expectEqual(await nestedBasePri, basePri)
          expectEqual(await nestedCurPri, curPri)

          let dispatchGroup = DispatchGroup()
          // Structured concurrency via task groups, escalated priority should
          // propagate
          await withTaskGroup(of: Void.self, returning: Void.self) { group in
            dispatchGroup.enter()
            group.addTask {
              let (childBasePri, childCurPri) = await getNestedTaskPriority()
              expectEqual(childBasePri, basePri)
              expectEqual(childCurPri, curPri)
              dispatchGroup.leave()
              return
            }

            dispatchGroup.enter()
            group.addTask(priority: .utility) {
              let (childBasePri, childCurPri) = await getNestedTaskPriority()
              expectEqual(childBasePri, .utility)
              expectEqual(childCurPri, curPri)
              dispatchGroup.leave()
              return
            }

            // Wait for child tasks to finish running, don't await since that will
            // escalate them
            dispatchGroup.wait()
          }
        }
      }

      tests.test("Unstructured base priority propagation") {
        Task(priority : .background) {
          await loopUntil(priority: .default)

          let basePri = Task.basePriority!
          let curPri = Task.currentPriority
          expectEqual(basePri, .background)
          expectEqual(curPri, .default)

          let group = DispatchGroup()

          // Create some unstructured tasks
          group.enter()
          Task {
            let (childBasePri, childCurPri) = await getNestedTaskPriority()
            expectEqual(childBasePri, basePri)
            expectEqual(childCurPri, childBasePri)
            group.leave()
            return
          }

          group.enter()
          Task(priority: .utility) {
            let (childBasePri, childCurPri) = await getNestedTaskPriority()
            expectEqual(childBasePri, .utility)
            expectEqual(childCurPri, childBasePri)
            group.leave()
            return
          }

          // Wait for child tasks to finish running, don't await since that will
          // escalate them
          group.wait()

        }
      }
    }
    await runAllTestsAsync()
  }
}
