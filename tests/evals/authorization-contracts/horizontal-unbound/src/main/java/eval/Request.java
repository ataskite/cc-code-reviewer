package eval;

final class Request {
    final String key;
    final Subject subject;

    Request(String key, Subject subject) {
        this.key = key;
        this.subject = subject;
    }
}
