package eval;

final class Two implements Beta {
    @Override
    public boolean b(Packet packet) {
        return packet.marker == null;
    }

    @Override
    public void c(Packet packet) {
        packet.next = true;
    }
}
