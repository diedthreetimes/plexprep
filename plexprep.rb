#!/usr/bin/env ruby

require 'yaml'
require 'net/http'
require 'nokogiri'

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

# Download Only if it doesn't already exist
# returns true on success
def download url, local_dir
  local_file = File.join(local_dir, File.basename(url))
  if File.size?( local_file )
    puts "Skipping #{File.basename(local_file)}"
    return false
  end


  system("wget #{url} -O #{local_file}")

  if !(File.size?( local_file ))
    warn "Download of #{File.basename(local_file)} failed."
    File.unlink( local_file)
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
  warn "Usage: #{File.basename($0)} url [library_type]"
  exit
end

if __FILE__ == $0
  if ARGV[0].nil?
    usage
  end

  yaml = YAML.load_file( config_file )

  directory = ARGV[0]
  library = (ARGV[1].nil? ? "tv" : ARGV[1])

  files = remote_ls yaml["host_address"], directory

  num_downloaded = 0
  files.each do |f|
    break if num_downloaded == yaml["max_downloads"].to_i

#    puts "About to download #{f}"
    if download f, yaml["plex"]["libraries"][library]["directory"]
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
