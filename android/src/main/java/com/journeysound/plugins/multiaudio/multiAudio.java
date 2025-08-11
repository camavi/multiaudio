package com.journeysound.plugins.multiaudio;

import com.getcapacitor.Logger;

public class MultiAudio {

    public String echo(String value) {
        Logger.info("Echo", value);
        return value;
    }
}
