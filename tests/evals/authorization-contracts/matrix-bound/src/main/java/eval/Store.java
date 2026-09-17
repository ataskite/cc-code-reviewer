package eval;

import java.util.List;

interface Store {
    Record find(String key);
    List<Record> findAll(List<String> keys);
}
