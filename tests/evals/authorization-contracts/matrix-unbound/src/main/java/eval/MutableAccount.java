package eval;

final class MutableAccount {
    String displayName;
    boolean privileged;

    void apply(String displayName, boolean privileged) {
        this.displayName = displayName;
        this.privileged = privileged;
    }
}
