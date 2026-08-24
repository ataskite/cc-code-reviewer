package eval;

final class Two implements Beta {
    @Override
    public boolean b(Packet packet) {
        return packet.marker == Decision.GRANTED;
    }

    @Override
    public void c(Packet packet) {
        packet.next = true;
    }
}
