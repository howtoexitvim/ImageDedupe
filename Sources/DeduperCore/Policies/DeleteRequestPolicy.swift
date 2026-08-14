public enum DeleteRequestPolicy {
    public static func shouldCallDeviceDelete(plannedDeleteCount: Int) -> Bool {
        plannedDeleteCount > 0
    }
}
