import Darwin

/// Scheduling facts about the current thread. Used once, on the first touch frame.
public enum ThreadInfo {
    public static func currentQoS() -> UInt32 {
        var qos = QOS_CLASS_UNSPECIFIED
        var relative: Int32 = 0
        pthread_get_qos_class_np(pthread_self(), &qos, &relative)
        return qos.rawValue
    }

    public static func qosName(_ raw: UInt32) -> String {
        switch raw {
        case QOS_CLASS_USER_INTERACTIVE.rawValue: "userInteractive"
        case QOS_CLASS_USER_INITIATED.rawValue: "userInitiated"
        case QOS_CLASS_DEFAULT.rawValue: "default"
        case QOS_CLASS_UTILITY.rawValue: "utility"
        case QOS_CLASS_BACKGROUND.rawValue: "background"
        case 0: "unspecified"
        default: "qos(\(raw))"
        }
    }

    /// Mach precedence and whether a time-constraint (real-time) policy is set.
    public static func currentScheduling() -> (precedence: Int32, timeConstraint: Bool) {
        let port = mach_thread_self()
        defer { mach_port_deallocate(mach_task_self_, port) }

        var precedence = thread_precedence_policy_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<thread_precedence_policy_data_t>.size / MemoryLayout<integer_t>.size)
        var getDefault: boolean_t = 0
        _ = withUnsafeMutablePointer(to: &precedence) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                thread_policy_get(port, thread_policy_flavor_t(THREAD_PRECEDENCE_POLICY), $0, &count, &getDefault)
            }
        }

        var constraint = thread_time_constraint_policy_data_t()
        var tcCount = mach_msg_type_number_t(MemoryLayout<thread_time_constraint_policy_data_t>.size / MemoryLayout<integer_t>.size)
        var tcDefault: boolean_t = 1
        _ = withUnsafeMutablePointer(to: &constraint) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(tcCount)) {
                thread_policy_get(port, thread_policy_flavor_t(THREAD_TIME_CONSTRAINT_POLICY), $0, &tcCount, &tcDefault)
            }
        }
        return (precedence.importance, tcDefault == 0)
    }
}
