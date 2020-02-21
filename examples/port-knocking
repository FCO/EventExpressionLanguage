event knocked-the-secret {
    has $ip = #1.ip;
    match {
        [
            knock(#1, port == 1, ?ip == #1.ip)
            knock(    port == 2, ?ip == #1.ip)
            knock(    port == 3, ?ip == #1.ip)
        ] ** 2
    }
}