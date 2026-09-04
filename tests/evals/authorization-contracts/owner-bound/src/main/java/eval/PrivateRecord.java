package eval;

final class PrivateRecord {
    final String ownerId;
    final String payload;

    PrivateRecord(String ownerId, String payload) {
        this.ownerId = ownerId;
        this.payload = payload;
    }
}
