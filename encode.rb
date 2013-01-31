#!/usr/bin/env ruby

require "fileutils"
require "pathname"
require "rubygems"
require "chunky_png"
require "json"

BLOCK_SIZE = 8

# how different a block has to be before it's considered different
# 0 means lossless
# a value of 0 kicks in a slightly faster algorithm
$diff_threshold = 0

def to_b64(i)
    v = nil
    if i < 26
        v = (i + 65)        # A-Z
    elsif i >= 26 && i < 52
        v = (i - 26 + 97)   # a-z
    elsif i >= 52 && i < 62
        v = (i - 52 + 48)   # 0-9
    elsif i == 62           
        v = 43              # +
    elsif i == 63
        v = 47              # /
    end
    raise "value out of bounds for base64 encode" if !v
    return v.chr
end   

def from_b64(c)
    i = c[0]
    v = nil
    if i >= 65 && i < 91
        v = i - 65          # A-Z
    elsif i >= 97 && i < 123
        v = i - 97 + 26     # a-z
    elsif i >= 48 && i < 58
        v = i - 48 + 52     # 0-9
    elsif i == 43
        v = 62              # +
    elsif i == 47
        v = 63              # /
    end
    raise "invalid character for base64 decode" if !v
    return v
end

class Encoder
    def initialize
        @frames = []
        @blocks = []
        @width = nil
        @height = nil
        @last_frame = nil
    end
    
    def self.frame_rle_encode(in_array)
        out_array = []
        last_val = nil
        val_count = 0

        in_array.each do |val|
            if (val != last_val) || val_count == 63
                if last_val == nil
                    # do nothing
                else
                    # emit value and count
                    if val_count == 1
                        # just emit value
                        out_array << last_val
                    else
                        # emit value with flag to indicate that a count will follow, then a count
                        out_array << ((1 << 5) | last_val)
                        out_array << val_count
                    end
                end
                last_val = val
                val_count = 0
            end
            val_count = val_count + 1
        end

        # emit last value
        if val_count == 1
            # just emit value
            out_array << last_val
        else
            # emit value with flag to indicate that a count will follow, then a count
            out_array << ((1 << 5) | last_val)
            out_array << val_count
        end
        out2 = []
        out_array.each do |v|
            out2 << to_b64(v)
        end
        return out2.join("")
    end
    
    def self.encode_frame_map(in_array)
        out_array = []
        (in_array.length / 4).times do |i|
            out_array << (
                (in_array[i*4] << 3) |
                (in_array[i*4 + 1] << 2) |
                (in_array[i*4 + 2] << 1) |
                (in_array[i*4 + 3]))
        end
        return Encoder.frame_rle_encode(out_array)
    end
    
    def add_frame(fname)
        if !@last_frame
            @last_frame = ChunkyPNG::Image.from_file(fname)
            return
        end
        
        image1 = @last_frame
        image2 = ChunkyPNG::Image.from_file(fname)
        
        if @width == nil
            @width = image1.width / BLOCK_SIZE
            @height = image1.height / BLOCK_SIZE
        end
        
        output_map = []
        diff_block_count = 0
        
        if $diff_threshold == 0 
            @height.times do |y|
                @width.times do |x|
                    diff = false
                    BLOCK_SIZE.times do |b_y|
                        BLOCK_SIZE.times do |b_x|
                            if image1[x*BLOCK_SIZE + b_x, y*BLOCK_SIZE + b_y] != image2[x*BLOCK_SIZE + b_x, y*BLOCK_SIZE + b_y]
                                diff = true
                                break
                            end
                        end
                    end
    
                    if diff
                        output_map << 1
                        diff_block_count = diff_block_count + 1
                    else
                        output_map << 0
                    end 
                end
            end
        else
            @height.times do |y|
                @width.times do |x|
                    # compare block data in the two images at x/y
                    #puts "comparing blocks #{x}/#{y}"
                    diff = 0
                    BLOCK_SIZE.times do |b_y|
                        BLOCK_SIZE.times do |b_x|
                            c1 = image1[x*BLOCK_SIZE + b_x, y*BLOCK_SIZE + b_y]
                            c2 = image2[x*BLOCK_SIZE + b_x, y*BLOCK_SIZE + b_y]
                            
                            diff = diff + #abs((c1 & 0x000000ff) - (c2 & 0x000000ff)) +
                                (((c1 & 0x0000ff00) >> 8) -  ((c2 & 0x0000ff00) >> 8)).abs +
                                (((c1 & 0x00ff0000) >> 16) - ((c2 & 0x00ff0000) >> 16)).abs +
                                (((c1 & 0xff000000) >> 24) - ((c2 & 0xff000000) >> 24)).abs
                        end
                    end
    
                    if diff > $diff_threshold
                        output_map << 1
                        diff_block_count = diff_block_count + 1
                    else
                        output_map << 0
                    end
                end
            end
        end
                
        # add frame map    
        puts "frame takes #{diff_block_count} blocks"
        @frames << Encoder.encode_frame_map(output_map)
        
        # create image with difference blocks
        #out_image = ChunkyPNG::Image.new(diff_block_count * BLOCK_SIZE, BLOCK_SIZE)
        block_count = 0
        @height.times do |y|
            @width.times do |x|
                if output_map[y * @width + x] == 1
                    blockdata = []
                    BLOCK_SIZE.times do |b_y|
                        BLOCK_SIZE.times do |b_x|
                            blockdata << image2[x*BLOCK_SIZE + b_x, y*BLOCK_SIZE + b_y]
                        end
                    end
                    @blocks << blockdata
                end
            end
        end
        
        @last_frame = image2
    end
    
    def write_blocks(out_fname)
        blocks_per_line = Math.sqrt(@blocks.length).floor
        
        out_image = ChunkyPNG::Image.new(blocks_per_line * BLOCK_SIZE, (@blocks.length / blocks_per_line + 1) * BLOCK_SIZE)
        @blocks.length.times do |i|
            block = @blocks[i]
            
            BLOCK_SIZE.times do |b_y|
                BLOCK_SIZE.times do |b_x|
                    out_image[(i % blocks_per_line) * BLOCK_SIZE + b_x, (i / blocks_per_line) * BLOCK_SIZE + b_y] = block[b_y * BLOCK_SIZE + b_x]
                end
            end
        end
        out_image.save(out_fname)
    end
    
    def metadata
        out = {
            "width" => @width,
            "height" => @height,
            "block_size" => BLOCK_SIZE,
            "frames" => @frames
        }
    end
    
    def write_metadata(name, out_fname)
        File.open(out_fname, "w") do |fh|
            fh.write("var #{name}Animation = ")
            fh.write(metadata.to_json)
            fh.write(";\n")
        end
    end
end

if __FILE__ == $0
    e = Encoder.new
    if ARGV.length < 2
        puts "Usage: #{$0} <shortname> <input directory>"
        exit(1)
    end
    
    out_name = ARGV[0]
    in_dir = ARGV[1]
    
    frame_files = Dir.entries(in_dir).find_all { |x| File.extname(x) == ".png" } .sort
    
    (frame_files.length).times do |i|
        puts "frame #{i+1}"
        
        e.add_frame(File.join(in_dir, frame_files[i]))
    end
    FileUtils.cp(File.join(in_dir, frame_files[0]), "#{out_name}_first.png")
    puts "Writing block data..."
    e.write_blocks("#{out_name}_blocks.png")
    puts "Writing metadata..."
    e.write_metadata(Pathname.new(out_name).basename, "#{out_name}_data.js")
    puts "Done!"
end
