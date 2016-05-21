#!/usr/bin/env ruby

require 'yaml'
require 'net/http'
require 'nokogiri'
require 'fileutils'

config_file = File.join(File.dirname( __FILE__), "config.yml").to_s

def remote_ls server, directory
  address =
    if directory =~ /http/
      directory
    else
      server + directory
    end

  url = URI.parse(address)
  req = Net::HTTP::Get.new(url.to_s)

  res = Net::HTTP.start(url.host, url.port) { |http|
    http.request(req)
  }

  if !res.kind_of? Net::HTTPSuccess
    warn "Problem contacting server."
    return []
  end

  page = Nokogiri::HTML( res.body )

  links = page.css('td a').collect {|x| address + x.attributes["href"].value }

  links.slice(1, links.length)
end

def sh_sanitize inp
  # Block syntax used to fix \\ in regex causing issues
  inp.gsub('(','\\(').gsub(')','\\)').gsub('\''){'\\\''}
end

def remote_filename url, wget_args, local_dir = nil
  if wget_args.nil? || wget_args == ""
    File.basename(url)
  else
    # TODO: This actually downloads the file again! Ugh...
    file_name = `wget #{wget_args} --server-response -q \"#{url}\" 2>&1 | grep \"Content-Disposition:\" | tail -1  | awk 'match($0, /filename=(.+)/, f){ print f[1] }'`.strip
    if file_name[0] == '"' && file_name[file_name.size-1] == '"'
      file_name = file_name.slice(1,file_name.size - 2)
    end

    FileUtils.mv(file_name, File.join(local_dir, file_name))

    File.join(local_dir, file_name)
  end
end

# Download Only if it doesn't already exist
# returns true on success
def download url, local_dir, wget_args = ""
  #TODO: Can we remove the need for this logic by using the -c option? If yes restructure to have local_file printed from wget using logic from remote_filename
  #    This is a good alternative to fixing the erraneous download in remote_filename
  # TODO: Fix double download in remote_filename and then uncomment this.
  local_file = nil

  if wget_args == ""
    local_file = remote_filename(url, wget_args, local_dir)
    if File.size?( local_file )
      puts "Skipping #{File.basename(local_file)}"
      return false
    end

    system("wget #{wget_args} #{sh_sanitize(url)} -O #{sh_sanitize(local_file)}")
  else
    # TODO: When remote_filename is fixed rework this logic (by removing this block)
    local_file = remote_filename(url, wget_args, local_dir)
  end

  if !(File.size?( local_file ))
    warn "Download of #{File.basename(local_file)} failed."
    if (File.exists?(local_file))
      File.unlink( local_file)
    end
    return false
  end

  true
end

def request_refresh yaml, library_id
  puts "Refreshing library #{library_id}"

  server = yaml["plex"]["address"]
  library = yaml["plex"]["libraries"][library_id]["id"]
  token = yaml["plex"]["cookie"]
  url = URI.parse(server + "/library/sections/#{library}/refresh")
  req = Net::HTTP::Get.new(url.to_s)

  req["X-Plex-Client-Identifier"] = token["identifier"]
  req["X-Plex-Device"] = "OSX"
  req["X-Plex-Device-Name"] = "Plex Web (Chrome)"
  req["X-Plex-Platform"] = "Chrome"
  req["X-Plex-Platform-Version"] = "35.0"
  req["X-Plex-Product"] = "Plex Web"
  req["X-Plex-Token"] = token["token"]
  req["X-Plex-Username"] = token["username"]
  req["X-Plex-Version"] = "2.1.12"

  res = Net::HTTP.start(url.host, url.port) { |http|
    http.request(req)
  }

  if !res.kind_of? Net::HTTPSuccess
    warn "Problem refreshing plex"
  end
end

def usage
  warn "Usage: #{File.basename($0)} [-p] url [library_type]"
  # With the -p option present the url shoudln't be present. lists of files to download are presented via stdin
  exit
end


# TODO: Integrate with Thor for easier command parsing and help

if __FILE__ == $0
  if ARGV[0].nil?
    usage
  end

  yaml = YAML.load_file( config_file )


  wget_args = ""
  files = []
  directory = nil
  library = nil
  create_directory = false

  if ARGV[0] == "-p" # put-io integration
    wget_args = "--content-disposition -c --http-user=#{yaml["storage_host"]["username"]} --http-password=#{yaml["storage_host"]["password"]}"
    while file = $stdin.gets
     files.push file
    end

    directory = ARGV[1]
    library = (ARGV[2].nil? ? "tv" : ARGV[2])

    create_directory = true

    puts "Downloading into #{library} /#{directory}"
  else # regular operation

    directory = ARGV[0]
    library = (ARGV[1].nil? ? "tv" : ARGV[1])

    files = remote_ls yaml["host_address"], directory
  end



  num_downloaded = 0
  files.each do |f|
    break if num_downloaded == yaml["max_downloads"].to_i

    local_dir = yaml["plex"]["libraries"][library]["directory"]

    if create_directory
      local_dir = File.join(local_dir, directory)
      FileUtils.mkdir(local_dir) unless File.exists?(local_dir)
    end

#    puts "About to download #{f}"
    if download f, local_dir, wget_args
      num_downloaded += 1

      # We may want to watch this as soon as it is done.
      if num_downloaded == 1
        request_refresh yaml, library
      end
    end
  end

  if num_downloaded > 1
    request_refresh yaml, library
  end
end
