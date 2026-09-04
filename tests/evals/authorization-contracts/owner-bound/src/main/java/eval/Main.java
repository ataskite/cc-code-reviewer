package eval;

public final class Main {

    public static void main(String[] args) {
        String key = args.length > 0 ? args[0] : "default-key";
        RecordStore store = new RecordStore() {
            @Override
            public PrivateRecord find(String key) {
                return new PrivateRecord("owner-9", "private-payload");
            }
        };
        ExternalSink sink = new ExternalSink() {
            @Override
            public void send(PrivateRecord record) {
                System.out.println(record.payload);
            }
        };
        new RecordFlow(store, sink).handle(new Request(key, new Subject("user-1")));
    }
}
