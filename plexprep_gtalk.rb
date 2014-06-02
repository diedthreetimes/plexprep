#!/usr/bin/env ruby
require 'easy-gtalk-bot'
require 'yaml'

ACCEPT_INVITES = false # Set this to false for increased security
DEFAULT_FIRST_SSH_COMMAND = "cd ~/public_html;"

config_file = File.join(File.dirname( __FILE__), "config.yml").to_s

yaml = YAML.load_file( config_file )["gtalk"]

bot = GTalk::Bot.new(:email => yaml["email"], :password => yaml["password"])
bot.get_online # TODO: extend easy-gtalk-bot to allow off the record chats.

bot.on_invitation do |inviter|
  puts "Invited by #{inviter}"

  # TODO: for some reason we only get a name, and not an email for an invite.
  #  we could try to check this here, instead we just check it at message time
  if ACCEPT_INVITES #&& yaml["valid_users"].include?( inviter )
    bot.accept_invitation(inviter)
    bot.message(inviter, "Hello there! Thanks for using plexprep.")
  end
end

download_command = File.join( File.dirname( __FILE__ ), "plexprep.rb")
bot.on_message do |from, text|
  # This authorization doesn't seem to be working!
  # if !yaml["valid_users"].include?( from )
  #   puts "No longer valid user #{from} sent #{text}"
  #   bot.message(from, "You are no longer authorized for this service.")
  #   next
  # end
  puts "Received #{text} from #{from}"

  next if text.nil?

  words = text.split("\u00a0")
  command = words[0]
  args = words.slice(1, words.length)

  if command =~ /sync/i
    puts "about to sync #{args} : #{text}"
    if args.length < 3 && args.length > 0
      puts "args correct"
      # TODO: For some reaosn breaking off to system interferes with the Thread.stop
      puts `#{download_command} #{args.join(" ")}`
      bot.message(from "Syncing....")
      #bot.message(from, `#{donwload_command} #{args}`)
    else
      bot.message(from, "Invalid number of arguments")
    end
  elsif command =~ /command/i
    # TODO: SSH code goes here
    bot.message(from, "Commands to the storage host are currently unsuported")
  elsif command =~ /help/i
    puts "about to send a message"
    bot.message(from, "Available commands " + "\n" +
                "  sync url [library]" + "\n" +
                "  command [any]" + "\n")
  end

end

#require 'pry'
#binding.pry

loop do
  sleep(1)
  Thread.stop
end
