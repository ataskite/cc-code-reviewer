package eval;

final class MutableAccount {
    String displayName;
    boolean privileged;

    void rename(String displayName) {
        this.displayName = displayName;
    }
}
