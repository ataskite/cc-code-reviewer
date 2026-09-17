package eval;

import java.util.List;

public final class Main {
    public static void main(String[] args) {
        Subject subject = new Subject("user-1", "tenant-1", "MEMBER");
        Request request = new Request(subject, "record-1", List.of("record-1"), "new-name", true);
        Store store = new Store() {
            public Record find(String key) { return new Record("user-1", "tenant-1", "private"); }
            public List<Record> findAll(List<String> keys) {
                return List.of(new Record("user-1", "tenant-1", "own"));
            }
        };
        Sink sink = new Sink() {
            public void emit(Record record) { System.out.println(record.payload()); }
            public void export(List<Record> records) { System.out.println(records.size()); }
            public void disableAccount(String accountId) { System.out.println(accountId); }
            public void save(MutableAccount account) { System.out.println(account.displayName); }
        };
        Flow flow = new Flow(store, sink);
        flow.read(request);
        flow.export(request);
        flow.administer(request);
        flow.update(request, new MutableAccount());
    }
}
