#! /usr/bin/env ruby

##########################################################
# thumbnailer.rb
#
# extract thumbnails from mp4s using csv source data
#
##########################################################

require 'trollop'
require 'fastercsv'
require 'timecode'

##########################################################
# PARAMETERS & ERROR CHECKING
##########################################################

MOVIE_ROOT='/movies'

# NOTE:  fps doesn't matter, we convert it away, just need an even number...

##########################################################
# COMMAND LINE PARSING
##########################################################

opts = Trollop::options do
  version "thumbnailer.rb v1.0 (c) 2011 Fandor.com / Our Film Festival, Inc."
  banner <<-EOS

thumbnailer.rb extracts thumbnails from source mp4s based on film ID & timecode

Usage:
    thumbnailer <file.csv>

thumbnailer expects file.csv to have a header row labeling three columns (in any order):
  Film ID                 = film id
  Title card timecode     = timecode for title card thumbnail
  Image 1 timecode        = timecode for image thumbnail 1
  Image 2 timecode        = timecode for image thumbnail 2
  Image 3 timecode        = timecode for image thumbnail 3

(Timecodes should be formatted as h:mm:ss or hh:mm:ss)
EOS
  opt :n_frames, "Number of frames to extract at each timecode", :default => 1
  opt :offset, "Number of seconds before each timecode to begin extracting", :default => 0.0
  opt :output_path, "Root folder for thumbnail output", :default => "./new_thumbnails"
  opt :dry_run, "Dry run (don't create thumbnails)", :default => false
end

csv_file = ARGV.shift
# validate options
Trollop::die "Input file #{csv_file} does not exist!" unless csv_file && File.exist?(csv_file)

$n_frames = opts[:n_frames]
$offset = Timecode.parse("00:00:%05.2f" % opts[:offset], 24)
$output_path = opts[:output_path]
$dry_run = opts[:dry_run]

# for a given film id, return the path to the largest associated mp4 file (presumably the highest quality file)
def largest_film_file(id)
  max_file = ''
  max_size = 0
  files = Dir.glob(File.join(MOVIE_ROOT, id[0..0], id, "*.mp4")) do |f|
    f_size = File.size(f)
    if f_size > max_size
      max_file = f
      max_size = f_size
    end
  end
  max_file
end

# parse a potentially flaky h:mm:ss timecode into a Timecode object (assuming 24 fps)
def parse_timecode(time_string)
  return unless time_string.is_a?(String)
  (h, m, s) = time_string.split(/:/).map { |e| e.to_i }
  begin
    Timecode.at(h, m, s, 0, 24)
  rescue
    # invalid timecode, return nil
    return nil
  end
end

def create_dir(d)
  if $dry_run
    puts "mkdir #{d}"
  else
    Dir.mkdir(d)
  end
end

def output_folder(id)
    # create output folders if necessary
    create_dir($output_path) unless File.exist?($output_path)
    path=File.join($output_path, id)
    create_dir(path) unless File.exist?(path)
    return path
end


def output_filename(id, timecode, title_card) 
    path=output_folder(id)

    # replace colons with underlines for filenames
    t = timecode.gsub(/:/, "_")

    if title_card
	return File.join(path, "#{id}_titlecard_#{t}_%02d.jpg")
    else
	return File.join(path, "#{id}_#{t}_%02d.jpg")
    end
end

def extract_thumbnail(source_file, timecode, id, title_card=false)

    # convert string into timecode; return if not valid
    t = parse_timecode(timecode)
    return unless t

    # subtract offset and convert into something ffmpeg will understand
    t = (t - $offset).with_frames_as_fraction
    # save multiple thumbnails before/after timecode 
    if $dry_run
      puts("ffmpeg -i #{source_file} -y -ss #{t} -vframes #{$n_frames} #{output_filename(id, t, title_card)}")
    else
      system("ffmpeg -i #{source_file} -y -ss #{t} -vframes #{$n_frames} #{output_filename(id, t, title_card)}")
    end
end

begin
  FasterCSV.foreach(csv_file, :headers => true, :header_converters => :symbol) do |row|
    id=row[:film_id]
    unless id.to_i > 0 
      puts "id #{row[:film_id]} is not valid!"
      next
    end

    source_file = largest_film_file(id) 
    unless source_file
      puts "could not find movie file for film id #{id}"
      next
    end

    extract_thumbnail(source_file, row[:title_card_timecode], id, true)
    extract_thumbnail(source_file, row[:image_1_timecode], id)
    extract_thumbnail(source_file, row[:image_2_timecode], id)
    extract_thumbnail(source_file, row[:image_3_timecode], id)

  end
end

