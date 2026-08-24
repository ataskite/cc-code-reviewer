package eval;

import java.util.List;

final class Flow {
    private final Alpha alpha;
    private final List<Beta> beta;
    private final Channel channel;

    Flow(Alpha alpha, List<Beta> beta, Channel channel) {
        this.alpha = alpha;
        this.beta = beta;
        this.channel = channel;
    }

    void run(Packet packet, String presented) {
        alpha.a(packet, presented);
        for (Beta item : beta) {
            if (item.b(packet)) {
                item.c(packet);
                break;
            }
        }
        if (packet.next) {
            channel.emit(packet);
        }
    }
}
