
var CanvasAnimHelper = {
    from_b64: function(c) {
        var i = c.charCodeAt(0);
        var v = null;
        
        if(i >= 65 && i < 91) {
            v = i - 65;         // A-Z
        } else if(i >= 97 && i < 123) {
            v = i - 97 + 26;    // a-z
        } else if(i >= 48 && i < 58) {
            v = i - 48 + 52;    // 0-9
        } else if(i == 43) {
            v = 62;             // +
        } else if(i == 47) {
            v = 63;             // /
        }
        //raise "invalid character for base64 decode" if !v
        return v
    },
    
    rle_decode: function(in_str) {
        var out = new Array();
        var i = 0;
        
        while(i < in_str.length) {
            val = CanvasAnimHelper.from_b64(in_str[i]);
            i = i + 1;
            if(val > 0xf) {
                val = val & 0xf;
                count = CanvasAnimHelper.from_b64(in_str[i]);
                for(var n=0; n < count; n++) {
                    out.push(val);
                }
                i = i + 1;
            } else {
                out.push(val);
            }
        }
        return out;
    }
}

function CanvasAnim(ctx, data, firstFrameURL, blocksURL) {
    this.ctx = ctx;
    this.data = data;
    this.firstFrameURL = firstFrameURL;
    this.blocksURL = blocksURL;
    
    this.redrawFirstFrame = function() {
        this.ctx.drawImage(this.firstFrameImg, 0, 0);
    }
    
    this.drawFirstFrame = function(framerate) {
        var a = this;
        this.firstFrameImg = new Image();
        this.firstFrameImg.onload = function() {
            a.redrawFirstFrame();
            a.animate(framerate);
        }
        this.firstFrameImg.src = this.firstFrameURL;
    }
        
    this.animate = function(framerate) {
        if(!this.firstFrameImg) {
            this.drawFirstFrame(framerate);
            return;
        }
        var a = this;

        var curFrame = 0;
        var curBlock = 0;
        
        var blockImg = new Image();
        blockImg.onload = function() {
            var BLOCK_SIZE = a.data.block_size;
            var blocksPerLine = blockImg.width / BLOCK_SIZE;
            
            var interval = setInterval(function() {
                if(curFrame == a.data.frames.length) {
                    // restart animation
                    curFrame = 0;
                    curBlock = 0;
                    a.redrawFirstFrame();
                } else {
                    var frame = CanvasAnimHelper.rle_decode(a.data.frames[curFrame]);
                    
                    for(var y = 0; y < a.data.height; y++) {
                        for(var x = 0; x < a.data.width; x++) {
                            var pos = y * a.data.width + x;
                            if(((frame[Math.floor(pos/4)] >> (3 - (pos % 4))) & 0x1) == 1) {
                                a.ctx.drawImage(blockImg,
                                    (curBlock % blocksPerLine) * BLOCK_SIZE,
                                    Math.floor(curBlock / blocksPerLine) * BLOCK_SIZE,
                                    BLOCK_SIZE, BLOCK_SIZE,
                                    x * BLOCK_SIZE, y * BLOCK_SIZE,
                                    BLOCK_SIZE, BLOCK_SIZE);
                                curBlock += 1;
                            }
                        }
                    }
                    curFrame = curFrame + 1;
                }                
            }, 1000/framerate);
        }
        
        blockImg.src = this.blocksURL;
        this.blockImg = blockImg;
    }
}

