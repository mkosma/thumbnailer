#! /usr/bin/env ruby

##########################################################
# thumbnailer.rb
#
# automatically extract thumbnails from mp4s
#
##########################################################

require 'trollop'
require 'fastercsv'
require 'timecode'
require 'ftools'

##########################################################
# PARAMETERS & ERROR CHECKING
##########################################################

MOVIE_ROOT='/movies'
FPS=24 # default, doesn't really matter, just used for format conversion seconds->frames

##########################################################
# COMMAND LINE PARSING
##########################################################

opts = Trollop::options do
  version "thumbnailer.rb v1.0 (c) 2011 Fandor.com / Our Film Festival, Inc."
  banner <<-EOS

thumbnailer.rb extracts thumbnails from source mp4s based on film ID & timecode

Usage:
    thumbnailer [file.csv]

thumbnailer expects file.csv to have a header row labeling three columns (in any order):
  Film ID                 = film id
  Title card timecode     = timecode for title card thumbnail
  Image 1 timecode        = timecode for image thumbnail 1
  Image 2 timecode        = timecode for image thumbnail 2
  Image 3 timecode        = timecode for image thumbnail 3

(Timecodes should be formatted as h:mm:ss or hh:mm:ss)
EOS
  opt :csv_file, "CSV file containing film ids and timecodes to extract", :type => String
  opt :film_id,  "Film ID to extract (if csv not specified)", :type => Integer, :default => 0
  opt :timecode, "Timecode to extract (if csv not specified)", :type => String
  opt :titlecard, "Is a single timecode extraction a timecode?", :default => false
  opt :image_as_default, "Copy image jpg to 000xid.jpg for default images (csv only)", :default => true
  opt :n_frames, "Number of frames to extract at each timecode", :default => 1
  opt :offset, "Number of seconds before each timecode to begin extracting", :default => 0.0
  opt :output_path, "Root folder for thumbnail output", :default => "./new_thumbnails"
  opt :dry_run, "Dry run (don't create thumbnails)", :default => false
end

$csv_file = opts[:csv_file]
$n_frames = opts[:n_frames]
$offset = opts[:offset]
$output_path = opts[:output_path]
$dry_run = opts[:dry_run]
$film_id = opts[:film_id]
$timecode = opts[:timecode]
$titlecard = opts[:titlecard]
$image_as_default = opts[:image_as_default]

# validate options
if $csv_file
  Trollop::die "Input file #{$csv_file} does not exist!" unless File.exist?($csv_file)
elsif $film_id > 0
  Trollop::die "Must specify a timecode to extract." unless $timecode
else 
  Trollop::die "Must specify a csv file, or a film id and timecode."
end

# for a given film id, return the path to the largest associated mp4 file (presumably the highest quality file)
def largest_film_file(id)
  max_file = ''
  max_size = 0
  id_dir = id / 100
  files = Dir.glob(File.join(MOVIE_ROOT, id_dir.to_s, id.to_s, "*.mp4")) do |f|
    f_size = File.size(f)
    if f_size > max_size
      max_file = f
      max_size = f_size
    end
  end
  max_file
end

# parse a potentially flaky h:mm:ss timecode into a Timecode object
def parse_timecode(time_string)
  return unless time_string.is_a?(String)
  (h, m, s) = time_string.split(/:/).map { |e| e.to_i }
  begin
    Timecode.at(h, m, s, 0, FPS)
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
    path=File.join($output_path, id.to_s)
    create_dir(path) unless File.exist?(path)
    return path
end

def output_filename(id, timecode, title_card) 
    path=output_folder(id)

    # replace colons with underlines for filenames
    t = timecode.gsub(/:/, "_")

    suffix = ($n_frames == 1) ? ".jpg" : "_%02d.jpg"

    if title_card
	return File.join(path, "#{id}_titlecard_#{t}#{suffix}")
    else
	return File.join(path, "#{id}_#{t}#{suffix}")
    end
end

def default_filename(id)
    path=output_folder(id)
    return File.join(path, "%06d.jpg" % id.to_i)
end

def extract_thumbnail(source_file, timecode, offset, id, title_card=false, as_default=false)
    # convert string into timecode; return if not valid
    t = parse_timecode(timecode)
    return unless t
    raise "Source file error!" unless source_file && File.exist?(source_file)

    # add offset seconds and convert into something ffmpeg will understand
    t = (t + offset * FPS).with_frames_as_fraction

    file = output_filename(id, t, title_card)

    if $dry_run
      puts("ffmpeg -i #{source_file} -y -ss #{t} -vframes #{$n_frames} #{file}")
    else
#      p = fork do
            puts "Exracting thumbnail from #{source_file}..."
            system("ffmpeg -i #{source_file} -y -ss #{t} -vframes #{$n_frames} #{file} &> /dev/null")
	    if as_default
	      File.copy(file, default_filename(id))
	    end      
#	  end
#      Process.detach(p)
    end
end

def extract_thumbnails_from_csv(csv_file)
  FasterCSV.foreach(csv_file, :headers => true, :header_converters => :symbol) do |row|

    # skip if the row is already marked "done"
    next if row[:done] && row[:done].downcase=="x"
    # skip if there are no timecodes identified
    next if (row[:title_card_timecode].to_s.length +
             row[:image_1_timecode].to_s.length +
             row[:image_2_timecode].to_s.length +
             row[:image_3_timecode].to_s.length) < 5

    id=row[:film_id].to_i
    unless id > 0 
      puts "id #{row[:film_id]} is not valid!"
      next
    end

    source_file = largest_film_file(id) 
    unless source_file && File.exist?(source_file)
      puts "could not find movie file #{source_file} for #{row[:published]=='TRUE' ? 'published' : 'unpublished'} film id #{id}" 
      next
    end

    extract_thumbnail(source_file, row[:title_card_timecode], -$offset, id, true, false)
    # use first image as default (000xxx.jpg)?
    extract_thumbnail(source_file, row[:image_1_timecode], -$offset, id, false, $image_as_default)
    extract_thumbnail(source_file, row[:image_2_timecode], -$offset, id)
    extract_thumbnail(source_file, row[:image_3_timecode], -$offset, id)
  end
end

def extract_single_timecode(id, timecode, titlecard)
  unless id > 0 
    puts "id #{id} is not valid!"
    return
  end

  source_file = largest_film_file(id) 
  unless source_file
    puts "could not find movie file #{source_file} for film id #{id}"
    return
  end
  extract_thumbnail(source_file, timecode, -$offset, id, titlecard)
end



################################################################################
## MAIN BODY
################################################################################

if $csv_file
   extract_thumbnails_from_csv($csv_file)
else
   extract_single_timecode($film_id, $timecode, $titlecard)
end

