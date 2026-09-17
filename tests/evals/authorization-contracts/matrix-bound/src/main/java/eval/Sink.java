package eval;

import java.util.List;

interface Sink {
    void emit(Record record);
    void export(List<Record> records);
    void disableAccount(String accountId);
    void save(MutableAccount account);
}
