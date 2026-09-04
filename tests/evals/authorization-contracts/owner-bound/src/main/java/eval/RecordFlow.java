package eval;

final class RecordFlow {
    private final RecordStore store;
    private final ExternalSink sink;

    RecordFlow(RecordStore store, ExternalSink sink) {
        this.store = store;
        this.sink = sink;
    }

    void handle(Request request) {
        PrivateRecord record = store.find(request.key);
        if (record == null) {
            return;
        }
        if (!request.subject.id.equals(record.ownerId)) {
            return;
        }
        sink.send(record);
    }
}
