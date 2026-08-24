package eval;

final class One implements Alpha {
    @Override
    public void a(Packet packet, String presented) {
        Boolean result = null;
        if (presented != null) {
            result = "ok".equals(presented) ? null : Boolean.FALSE;
        }
        packet.marker = result;
    }
}
