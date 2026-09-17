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
        if (record != null) {
            sink.emit(record);
        }
    }

    void export(Request request) {
        List<Record> records = store.findAll(request.recordKeys());
        sink.export(records);
    }

    void administer(Request request) {
        sink.disableAccount(request.recordKey());
    }

    void update(Request request, MutableAccount account) {
        account.apply(request.displayName(), request.privileged());
        sink.save(account);
    }
}
