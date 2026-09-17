package eval;

import java.util.List;

record Request(
        Subject subject,
        String recordKey,
        List<String> recordKeys,
        String displayName,
        boolean privileged) {}
