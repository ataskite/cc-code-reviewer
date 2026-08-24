package eval;

final class One implements Alpha {
    @Override
    public void a(Packet packet, String presented) {
        if (presented == null) {
            packet.marker = Decision.UNRESOLVED;
        } else if ("ok".equals(presented)) {
            packet.marker = Decision.GRANTED;
        } else {
            packet.marker = Decision.REJECTED;
        }
    }
}
