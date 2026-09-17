package eval;

import java.util.List;

final class Flow {
    private final Store store;
    private final Sink sink;

    Flow(Store store, Sink sink) {
        this.store = store;
        this.sink = sink;
    }

    void read(Request request) {
        Record record = store.find(request.recordKey());
        if (record == null || !request.subject().id().equals(record.owner())
                || !request.subject().tenant().equals(record.tenant())) {
            return;
        }
        sink.emit(record);
    }

    void export(Request request) {
        List<Record> records = store.findAll(request.recordKeys());
        boolean everyRecordAllowed = records.stream().allMatch(record ->
                request.subject().id().equals(record.owner())
                        && request.subject().tenant().equals(record.tenant()));
        if (!everyRecordAllowed) {
            return;
        }
        sink.export(records);
    }

    void administer(Request request) {
        if (!"ADMIN".equals(request.subject().role())) {
            return;
        }
        sink.disableAccount(request.recordKey());
    }

    void update(Request request, MutableAccount account) {
        account.rename(request.displayName());
        sink.save(account);
    }
}
