require 'spec_helper'

describe "Subscriber Properties" do
  let(:config) do
    {
      :authorized_channels_only => "off",
      :header_template => "HEADER\r\nTEMPLATE\r\n1234\r\n",
      :content_type => "custom content type",
      :subscriber_connection_ttl => "1s",
      :ping_message_interval => "2s"
    }
  end

  it "should not accept access without a channel path" do
    nginx_run_server(config, :timeout => 5) do |conf|
      EventMachine.run do
        sub = EventMachine::HttpRequest.new(nginx_address + '/sub/').get :head => headers, :timeout => 30
        sub.callback do
          sub.response_header.content_length.should eql(0)
          sub.response_header.status.should eql(400)
          sub.response_header['X_NGINX_PUSHSTREAM_EXPLAIN'].should eql("No channel id provided.")
          EventMachine.stop
        end
      end
    end
  end

  it "should check accepted methods" do
    nginx_run_server(config, :timeout => 5) do |conf|
      # testing OPTIONS method, EventMachine::HttpRequest does not have support to it
      socket = open_socket(nginx_host, nginx_port)
      socket.print("OPTIONS /sub/ch_test_accepted_methods_0 HTTP/1.0\r\n\r\n")
      headers, body = read_response_on_socket(socket)
      headers.should match_the_pattern(/HTTP\/1\.1 200 OK/)
      headers.should match_the_pattern(/Content-Length: 0/)

      EventMachine.run do
        multi = EventMachine::MultiRequest.new

        multi.add(:a, EventMachine::HttpRequest.new(nginx_address + '/sub/ch_test_accepted_methods_1').head)
        multi.add(:b, EventMachine::HttpRequest.new(nginx_address + '/sub/ch_test_accepted_methods_2').put(:body => 'body'))
        multi.add(:c, EventMachine::HttpRequest.new(nginx_address + '/sub/ch_test_accepted_methods_3').post)
        multi.add(:d, EventMachine::HttpRequest.new(nginx_address + '/sub/ch_test_accepted_methods_4').delete)
        multi.add(:e, EventMachine::HttpRequest.new(nginx_address + '/sub/ch_test_accepted_methods_5').get)

        multi.callback do
          multi.responses[:callback].length.should eql(5)

          multi.responses[:callback][:a].response_header.status.should eql(405)
          multi.responses[:callback][:a].req.method.should eql("HEAD")
          multi.responses[:callback][:a].response_header['ALLOW'].should eql("GET")

          multi.responses[:callback][:b].response_header.status.should eql(405)
          multi.responses[:callback][:b].req.method.should eql("PUT")
          multi.responses[:callback][:b].response_header['ALLOW'].should eql("GET")

          multi.responses[:callback][:c].response_header.status.should eql(405)
          multi.responses[:callback][:c].req.method.should eql("POST")
          multi.responses[:callback][:c].response_header['ALLOW'].should eql("GET")

          multi.responses[:callback][:d].response_header.status.should eql(405)
          multi.responses[:callback][:d].req.method.should eql("DELETE")
          multi.responses[:callback][:d].response_header['ALLOW'].should eql("GET")

          multi.responses[:callback][:e].response_header.status.should_not eql(405)
          multi.responses[:callback][:e].req.method.should eql("GET")

          EventMachine.stop
        end
      end
    end
  end

  it "should not accept access to a channel with id 'ALL'" do
    channel = 'ALL'

    nginx_run_server(config, :timeout => 5) do |conf|
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_1.callback do
          sub_1.response_header.status.should eql(403)
          sub_1.response_header.content_length.should eql(0)
          sub_1.response_header['X_NGINX_PUSHSTREAM_EXPLAIN'].should eql("Channel id not authorized for this method.")
          EventMachine.stop
        end
      end
    end
  end

  it "should not accept access to a channel with id containing wildcard" do
    channel_1 = 'abcd*efgh'
    channel_2 = '*abcdefgh'
    channel_3 = 'abcdefgh*'

    nginx_run_server(config, :timeout => 5) do |conf|
      EventMachine.run do
        multi = EventMachine::MultiRequest.new

        multi.add(:a, EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel_1).get(:head => headers, :timeout => 30))
        multi.add(:b, EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel_2).get(:head => headers, :timeout => 30))
        multi.add(:c, EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel_3).get(:head => headers, :timeout => 30))
        multi.callback do
          multi.responses[:callback].length.should eql(3)
          multi.responses[:callback].each do |name, response|
            response.response_header.status.should eql(403)
            response.response_header.content_length.should eql(0)
            response.response_header['X_NGINX_PUSHSTREAM_EXPLAIN'].should eql("Channel id not authorized for this method.")
          end

          EventMachine.stop
        end
      end
    end
  end

  it "should accept access to multiple channels" do
    nginx_run_server(config, :timeout => 5) do |conf|
      EventMachine.run do
        multi = EventMachine::MultiRequest.new

        multi.add(:a, EventMachine::HttpRequest.new(nginx_address + '/sub/ch_multi_channels_1').get)
        multi.add(:b, EventMachine::HttpRequest.new(nginx_address + '/sub/ch_multi_channels_1.b10').get)
        multi.add(:c, EventMachine::HttpRequest.new(nginx_address + '/sub/ch_multi_channels_2/ch_multi_channels_3').get)
        multi.add(:d, EventMachine::HttpRequest.new(nginx_address + '/sub/ch_multi_channels_2.b2/ch_multi_channels_3').get)
        multi.add(:e, EventMachine::HttpRequest.new(nginx_address + '/sub/ch_multi_channels_2/ch_multi_channels_3.b3').get)
        multi.add(:f, EventMachine::HttpRequest.new(nginx_address + '/sub/ch_multi_channels_2.b2/ch_multi_channels_3.b3').get)
        multi.add(:g, EventMachine::HttpRequest.new(nginx_address + '/sub/ch_multi_channels_4.b').get)

        multi.callback do
          multi.responses[:callback].length.should eql(7)
          multi.responses[:callback].each do |name, response|
            response.response_header.status.should eql(200)
          end

          EventMachine.stop
        end
      end
    end
  end

  it "should not accept access with a big channel id" do
    channel = '123456'

    nginx_run_server(config.merge(:max_channel_id_length => 5), :timeout => 5) do |conf|
      EventMachine.run do
        sub = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s ).get :head => headers, :timeout => 30
        sub.callback do
          sub.response_header.content_length.should eql(0)
          sub.response_header.status.should eql(400)
          sub.response_header['X_NGINX_PUSHSTREAM_EXPLAIN'].should eql("Channel id is too large.")
          EventMachine.stop
        end
      end
    end
  end

  it "should not accept access to a broadcast channel without a normal channel" do
    nginx_run_server(config.merge(:broadcast_channel_prefix => "bd_"), :timeout => 5) do |conf|
      EventMachine.run do
        multi = EventMachine::MultiRequest.new

        multi.add(:a, EventMachine::HttpRequest.new(nginx_address + '/sub/bd_test_broadcast_channels_without_common_channel').get)
        multi.add(:b, EventMachine::HttpRequest.new(nginx_address + '/sub/bd_').get)
        multi.add(:c, EventMachine::HttpRequest.new(nginx_address + '/sub/bd1').get)
        multi.add(:d, EventMachine::HttpRequest.new(nginx_address + '/sub/bd').get)

        multi.callback do
          multi.responses[:callback].length.should eql(4)

          multi.responses[:callback][:a].response_header.content_length.should eql(0)
          multi.responses[:callback][:a].response_header.status.should eql(403)
          multi.responses[:callback][:a].response_header['X_NGINX_PUSHSTREAM_EXPLAIN'].should eql("Subscribed too much broadcast channels.")
          multi.responses[:callback][:a].req.uri.to_s.should eql(nginx_address + '/sub/bd_test_broadcast_channels_without_common_channel')

          multi.responses[:callback][:b].response_header.content_length.should eql(0)
          multi.responses[:callback][:b].response_header.status.should eql(403)
          multi.responses[:callback][:b].response_header['X_NGINX_PUSHSTREAM_EXPLAIN'].should eql("Subscribed too much broadcast channels.")
          multi.responses[:callback][:b].req.uri.to_s.should eql(nginx_address + '/sub/bd_')

          multi.responses[:callback][:c].response_header.status.should eql(200)
          multi.responses[:callback][:c].req.uri.to_s.should eql(nginx_address + '/sub/bd1')

          multi.responses[:callback][:d].response_header.status.should eql(200)
          multi.responses[:callback][:d].req.uri.to_s.should eql(nginx_address + '/sub/bd')

          EventMachine.stop
        end
      end
    end
  end

  it "should accept access to a broadcast channel with a normal channel" do
    nginx_run_server(config.merge(:broadcast_channel_prefix => "bd_", :broadcast_channel_max_qtd => 2, :authorized_channels_only => "off"), :timeout => 5) do |conf|
      EventMachine.run do
        multi = EventMachine::MultiRequest.new

        multi.add(:a, EventMachine::HttpRequest.new(nginx_address + '/sub/bd1/bd2/bd3/bd4/bd_1/bd_2/bd_3').get)
        multi.add(:b, EventMachine::HttpRequest.new(nginx_address + '/sub/bd1/bd2/bd_1/bd_2').get)
        multi.add(:c, EventMachine::HttpRequest.new(nginx_address + '/sub/bd1/bd_1').get)
        multi.add(:d, EventMachine::HttpRequest.new(nginx_address + '/sub/bd1/bd2').get)

        multi.callback do
          multi.responses[:callback].length.should eql(4)

          multi.responses[:callback][:a].response_header.content_length.should eql(0)
          multi.responses[:callback][:a].response_header.status.should eql(403)
          multi.responses[:callback][:a].response_header['X_NGINX_PUSHSTREAM_EXPLAIN'].should eql("Subscribed too much broadcast channels.")
          multi.responses[:callback][:a].req.uri.to_s.should eql(nginx_address + '/sub/bd1/bd2/bd3/bd4/bd_1/bd_2/bd_3')

          multi.responses[:callback][:b].response_header.status.should eql(200)
          multi.responses[:callback][:b].req.uri.to_s.should eql(nginx_address + '/sub/bd1/bd2/bd_1/bd_2')

          multi.responses[:callback][:c].response_header.status.should eql(200)
          multi.responses[:callback][:c].req.uri.to_s.should eql(nginx_address + '/sub/bd1/bd_1')

          multi.responses[:callback][:d].response_header.status.should eql(200)
          multi.responses[:callback][:d].req.uri.to_s.should eql(nginx_address + '/sub/bd1/bd2')

          EventMachine.stop
        end
      end
    end
  end

  it "should not accept access to an nonexistent channel with authorized only 'on'" do
    channel = 'ch_test_subscribe_an_absent_channel_with_authorized_only_on'

    nginx_run_server(config.merge(:authorized_channels_only => 'on'), :timeout => 5) do |conf|
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_1.callback do
          sub_1.response_header.status.should eql(403)
          sub_1.response_header.content_length.should eql(0)
          sub_1.response_header['X_NGINX_PUSHSTREAM_EXPLAIN'].should eql("Subscriber could not create channels.")
          EventMachine.stop
        end
      end
    end
  end

  it "should accept access to an existent channel with authorized channel only 'on'" do
    channel = 'ch_test_subscribe_an_existing_channel_with_authorized_only_on'
    body = 'body'

    nginx_run_server(config.merge(:authorized_channels_only => 'on'), :timeout => 5) do |conf|
      #create channel
      publish_message(channel, headers, body)

      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_1.callback do
          sub_1.response_header.status.should eql(200)
          EventMachine.stop
        end
      end
    end
  end

  it "should accept access to an existing channel and a nonexistent broadcast channel with authorized only 'on'" do
    channel = 'ch_test_subscribe_an_existing_channel_and_absent_broadcast_channel_with_authorized_only_on'
    broadcast_channel = 'bd_test_subscribe_an_existing_channel_and_absent_broadcast_channel_with_authorized_only_on'

    body = 'body'

    nginx_run_server(config.merge(:authorized_channels_only => 'on', :broadcast_channel_prefix => "bd_", :broadcast_channel_max_qtd => 1), :timeout => 5) do |conf|
      #create channel
      publish_message(channel, headers, body)

      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s + '/' + broadcast_channel.to_s).get :head => headers, :timeout => 30
        sub_1.callback do
          sub_1.response_header.status.should eql(200)
          EventMachine.stop
        end
      end
    end
  end

  it "should not accept access to an existing channel without messages with authorized only 'on'" do
    channel = 'ch_test_subscribe_an_existing_channel_without_messages_and_with_authorized_only_on'

    body = 'body'

    nginx_run_server(config.merge(:authorized_channels_only => 'on', :message_ttl => "1s"), :timeout => 10) do |conf|
      #create channel
      publish_message(channel, headers, body)
      sleep(5) #to ensure message was gone

      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_1.callback do
          sub_1.response_header.status.should eql(403)
          sub_1.response_header.content_length.should eql(0)
          sub_1.response_header['X_NGINX_PUSHSTREAM_EXPLAIN'].should eql("Subscriber could not create channels.")
          EventMachine.stop
        end
      end
    end
  end

  it "should not accept access to an existing channel without messages and an nonexistent broadcast channel with authorized only 'on'" do
    channel = 'ch_test_subscribe_an_existing_channel_without_messages_and_absent_broadcast_channel_and_with_authorized_only_on_should_fail'
    broadcast_channel = 'bd_test_subscribe_an_existing_channel_without_messages_and_absent_broadcast_channel_and_with_authorized_only_on_should_fail'

    body = 'body'

    nginx_run_server(config.merge(:authorized_channels_only => 'on', :message_ttl => "1s", :broadcast_channel_prefix => "bd_", :broadcast_channel_max_qtd => 1), :timeout => 10) do |conf|
      #create channel
      publish_message(channel, headers, body)
      sleep(5) #to ensure message was gone

      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s + '/' + broadcast_channel.to_s).get :head => headers, :timeout => 30
        sub_1.callback do
          sub_1.response_header.status.should eql(403)
          sub_1.response_header.content_length.should eql(0)
          sub_1.response_header['X_NGINX_PUSHSTREAM_EXPLAIN'].should eql("Subscriber could not create channels.")
          EventMachine.stop
        end
      end
    end
  end

  it "should receive old messages in multi channel subscriber" do
    channel_1 = 'ch_test_retreive_old_messages_in_multichannel_subscribe_1'
    channel_2 = 'ch_test_retreive_old_messages_in_multichannel_subscribe_2'
    channel_3 = 'ch_test_retreive_old_messages_in_multichannel_subscribe_3'

    body = 'body'

    response = ""
    nginx_run_server(config.merge(:header_template => 'HEADER', :message_template => '{\"channel\":\"~channel~\", \"id\":\"~id~\", \"message\":\"~text~\"}'), :timeout => 5) do |conf|
      #create channels with some messages
      1.upto(3) do |i|
        publish_message(channel_1, headers, body + i.to_s)
        publish_message(channel_2, headers, body + i.to_s)
        publish_message(channel_3, headers, body + i.to_s)
      end

      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel_1.to_s + '/' + channel_2.to_s + '.b5' + '/' + channel_3.to_s + '.b2').get :head => headers, :timeout => 30
        sub_1.stream do |chunk|
          response += chunk
          lines = response.split("\r\n")

          if lines.length >= 6
            lines[0].should eql('HEADER')
            line = JSON.parse(lines[1])
            line['channel'].should eql(channel_2.to_s)
            line['message'].should eql('body1')
            line['id'].to_i.should eql(1)

            line = JSON.parse(lines[2])
            line['channel'].should eql(channel_2.to_s)
            line['message'].should eql('body2')
            line['id'].to_i.should eql(2)

            line = JSON.parse(lines[3])
            line['channel'].should eql(channel_2.to_s)
            line['message'].should eql('body3')
            line['id'].to_i.should eql(3)

            line = JSON.parse(lines[4])
            line['channel'].should eql(channel_3.to_s)
            line['message'].should eql('body2')
            line['id'].to_i.should eql(2)

            line = JSON.parse(lines[5])
            line['channel'].should eql(channel_3.to_s)
            line['message'].should eql('body3')
            line['id'].to_i.should eql(3)

            EventMachine.stop
          end
        end
      end
    end
  end

  it "should receive new messages in a multi channel subscriber" do
    channel_1 = 'test_retreive_new_messages_in_multichannel_subscribe_1'
    channel_2 = 'test_retreive_new_messages_in_multich_subscribe_2'
    channel_3 = 'test_retreive_new_messages_in_multchannel_subscribe_3'
    channel_4 = 'test_retreive_new_msgs_in_multichannel_subscribe_4'
    channel_5 = 'test_retreive_new_messages_in_multichannel_subs_5'
    channel_6 = 'test_retreive_new_msgs_in_multichannel_subs_6'

    body = 'body'

    response = ""
    nginx_run_server(config.merge(:header_template => nil, :message_template => '{\"channel\":\"~channel~\", \"id\":\"~id~\", \"message\":\"~text~\"}'), :timeout => 5) do |conf|
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel_1.to_s + '/' + channel_2.to_s + '/' + channel_3.to_s + '/' + channel_4.to_s + '/' + channel_5.to_s + '/' + channel_6.to_s).get :head => headers, :timeout => 30
        sub_1.stream do |chunk|
          response += chunk
          lines = response.split("\r\n")

          if lines.length >= 6
            line = JSON.parse(lines[0])
            line['channel'].should eql(channel_1.to_s)
            line['message'].should eql('body' + channel_1.to_s)
            line['id'].to_i.should eql(1)

            line = JSON.parse(lines[1])
            line['channel'].should eql(channel_2.to_s)
            line['message'].should eql('body' + channel_2.to_s)
            line['id'].to_i.should eql(1)

            line = JSON.parse(lines[2])
            line['channel'].should eql(channel_3.to_s)
            line['message'].should eql('body' + channel_3.to_s)
            line['id'].to_i.should eql(1)

            line = JSON.parse(lines[3])
            line['channel'].should eql(channel_4.to_s)
            line['message'].should eql('body' + channel_4.to_s)
            line['id'].to_i.should eql(1)

            line = JSON.parse(lines[4])
            line['channel'].should eql(channel_5.to_s)
            line['message'].should eql('body' + channel_5.to_s)
            line['id'].to_i.should eql(1)

            line = JSON.parse(lines[5])
            line['channel'].should eql(channel_6.to_s)
            line['message'].should eql('body' + channel_6.to_s)
            line['id'].to_i.should eql(1)

            EventMachine.stop
          end
        end

        publish_message_inline(channel_1, headers, body + channel_1.to_s)
        publish_message_inline(channel_2, headers, body + channel_2.to_s)
        publish_message_inline(channel_3, headers, body + channel_3.to_s)
        publish_message_inline(channel_4, headers, body + channel_4.to_s)
        publish_message_inline(channel_5, headers, body + channel_5.to_s)
        publish_message_inline(channel_6, headers, body + channel_6.to_s)
      end
    end
  end

  it "should receive old messages in a multi channel subscriber using 'if_modified_since' header" do
    channel_1 = 'ch_test_retreive_old_messages_in_multichannel_subscribe_using_if_modified_since_header_1'
    channel_2 = 'ch_test_retreive_old_messages_in_multichannel_subscribe_using_if_modified_since_header_2'
    channel_3 = 'ch_test_retreive_old_messages_in_multichannel_subscribe_using_if_modified_since_header_3'

    body = 'body'

    nginx_run_server(config.merge(:header_template => 'HEADER', :message_template => '{\"channel\":\"~channel~\", \"id\":\"~id~\", \"message\":\"~text~\"}'), :timeout => 40) do |conf|
      #create channels with some messages with progressive interval (2,4,6,10,14,18,24,30,36 seconds)
      1.upto(3) do |i|
        sleep(i * 2)
        publish_message(channel_1, headers, body + i.to_s)
        sleep(i * 2)
        publish_message(channel_2, headers, body + i.to_s)
        sleep(i * 2)
        publish_message(channel_3, headers, body + i.to_s)
      end

      #get messages published less then 20 seconds ago
      t = Time.now
      t = t - 20

      sent_headers = headers.merge({'If-Modified-Since' => t.utc.strftime("%a, %d %b %Y %T %Z")})

      response = ""
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel_1.to_s + '/' + channel_2.to_s + '/' + channel_3.to_s).get :head => sent_headers, :timeout => 30
        sub_1.stream do |chunk|
          response += chunk
          lines = response.split("\r\n")

          if lines.length >= 5
            lines[0].should eql('HEADER')

            line = JSON.parse(lines[1])
            line['channel'].should eql(channel_1.to_s)
            line['message'].should eql('body3')
            line['id'].to_i.should eql(3)

            line = JSON.parse(lines[2])
            line['channel'].should eql(channel_2.to_s)
            line['message'].should eql('body3')
            line['id'].to_i.should eql(3)

            line = JSON.parse(lines[3])
            line['channel'].should eql(channel_3.to_s)
            line['message'].should eql('body2')
            line['id'].to_i.should eql(2)

            line = JSON.parse(lines[4])
            line['channel'].should eql(channel_3.to_s)
            line['message'].should eql('body3')
            line['id'].to_i.should eql(3)

            EventMachine.stop
          end
        end
      end
    end
  end

  it "should receive old messages in a multi channel subscriber using 'if_modified_since' header and backtrack mixed" do
    channel_1 = 'ch_test_retreive_old_messages_in_multichannel_subscribe_using_if_modified_since_header_and_backtrack_mixed_1'
    channel_2 = 'ch_test_retreive_old_messages_in_multichannel_subscribe_using_if_modified_since_header_and_backtrack_mixed_2'
    channel_3 = 'ch_test_retreive_old_messages_in_multichannel_subscribe_using_if_modified_since_header_and_backtrack_mixed_3'

    body = 'body'

    nginx_run_server(config.merge(:header_template => 'HEADER', :message_template => '{\"channel\":\"~channel~\", \"id\":\"~id~\", \"message\":\"~text~\"}'), :timeout => 40) do |conf|
      #create channels with some messages with progressive interval (2,4,6,10,14,18,24,30,36 seconds)
      1.upto(3) do |i|
        sleep(i * 2)
        publish_message(channel_1, headers, body + i.to_s)
        sleep(i * 2)
        publish_message(channel_2, headers, body + i.to_s)
        sleep(i * 2)
        publish_message(channel_3, headers, body + i.to_s)
      end

      #get messages published less then 20 seconds ago
      t = Time.now
      t = t - 20

      sent_headers = headers.merge({'If-Modified-Since' => t.utc.strftime("%a, %d %b %Y %T %Z")})

      response = ""
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel_1.to_s + '/' + channel_2.to_s + '.b5' + '/' + channel_3.to_s).get :head => sent_headers, :timeout => 30
        sub_1.stream do |chunk|
          response += chunk
          lines = response.split("\r\n")

          if lines.length >= 7
            lines[0].should eql('HEADER')

            line = JSON.parse(lines[1])
            line['channel'].should eql(channel_1.to_s)
            line['message'].should eql('body3')
            line['id'].to_i.should eql(3)

            line = JSON.parse(lines[2])
            line['channel'].should eql(channel_2.to_s)
            line['message'].should eql('body1')
            line['id'].to_i.should eql(1)

            line = JSON.parse(lines[3])
            line['channel'].should eql(channel_2.to_s)
            line['message'].should eql('body2')
            line['id'].to_i.should eql(2)

            line = JSON.parse(lines[4])
            line['channel'].should eql(channel_2.to_s)
            line['message'].should eql('body3')
            line['id'].to_i.should eql(3)

            line = JSON.parse(lines[5])
            line['channel'].should eql(channel_3.to_s)
            line['message'].should eql('body2')
            line['id'].to_i.should eql(2)

            line = JSON.parse(lines[6])
            line['channel'].should eql(channel_3.to_s)
            line['message'].should eql('body3')
            line['id'].to_i.should eql(3)

            EventMachine.stop
          end
        end
      end
    end
  end

  it "should limit the number of channels" do
    channel = 'ch_test_max_number_of_channels_'

    nginx_run_server(config.merge(:max_number_of_channels => 1), :timeout => 5) do |conf|
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s + 1.to_s).get :head => headers, :timeout => 30
        sub_1.stream do
          sub_1.response_header.status.should eql(200)
          sub_1.response_header.content_length.should_not eql(0)

          sub_2 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s + 2.to_s).get :head => headers, :timeout => 30
          sub_2.callback do
            sub_2.response_header.status.should eql(403)
            sub_2.response_header.content_length.should eql(0)
            sub_2.response_header['X_NGINX_PUSHSTREAM_EXPLAIN'].should eql("Number of channels were exceeded.")
            EventMachine.stop
          end
        end
      end
    end
  end

  it "should limit the number of broadcast channels" do
    channel = 'bd_test_max_number_of_broadcast_channels_'

    nginx_run_server(config.merge(:max_number_of_broadcast_channels => 1, :broadcast_channel_prefix => 'bd_', :broadcast_channel_max_qtd => 1), :timeout => 5) do |conf|
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/ch1/' + channel.to_s + 1.to_s).get :head => headers, :timeout => 30
        sub_1.stream do
          sub_1.response_header.status.should eql(200)
          sub_1.response_header.content_length.should_not eql(0)

          sub_2 = EventMachine::HttpRequest.new(nginx_address + '/sub/ch1/' + channel.to_s + 2.to_s).get :head => headers, :timeout => 30
          sub_2.callback do
            sub_2.response_header.status.should eql(403)
            sub_2.response_header.content_length.should eql(0)
            sub_2.response_header['X_NGINX_PUSHSTREAM_EXPLAIN'].should eql("Number of channels were exceeded.")
            EventMachine.stop
          end
        end
      end
    end
  end


  it "should accept different message templates in each location" do
    configuration = config.merge({
      :message_template => '{\"text\":\"~text~\"}',
      :header_template => nil,
      :extra_location => %q{
        location ~ /sub2/(.*)? {
          # activate subscriber mode for this location
          push_stream_subscriber;

          # positional channel path
          set $push_stream_channels_path          $1;
          # message template
          push_stream_message_template "{\"msg\":\"~text~\"}";
        }

      }
    })

    channel = 'ch_test_different_message_templates'
    body = 'body'

    nginx_run_server(configuration, :timeout => 5) do |conf|
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_1.stream do |chunk|
          response = JSON.parse(chunk)
          response['msg'].should be_nil
          response['text'].should eql(body)
          EventMachine.stop
        end

        sub_2 = EventMachine::HttpRequest.new(nginx_address + '/sub2/' + channel.to_s + '.b1').get :head => headers, :timeout => 30
        sub_2.stream do |chunk|
          response = JSON.parse(chunk)
          response['text'].should be_nil
          response['msg'].should eql(body)
          EventMachine.stop
        end

        #publish a message
        publish_message_inline(channel, headers, body)
      end

      EventMachine.run do
        sub_3 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s + '.b1').get :head => headers, :timeout => 30
        sub_3.stream do |chunk|
          response = JSON.parse(chunk)
          response['msg'].should be_nil
          response['text'].should eql(body)
          EventMachine.stop
        end
      end

      EventMachine.run do
        sub_4 = EventMachine::HttpRequest.new(nginx_address + '/sub2/' + channel.to_s + '.b1').get :head => headers, :timeout => 30
        sub_4.stream do |chunk|
          response = JSON.parse(chunk)
          response['text'].should be_nil
          response['msg'].should eql(body)
          EventMachine.stop
        end
      end
    end
  end

  it "should use default message template" do
    channel = 'ch_test_default_message_template'
    body = 'body'

    nginx_run_server(config.merge(:message_template => nil, :header_template => nil), :timeout => 5) do |conf|
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_1.stream do |chunk|
          chunk.should eql("#{body}\r\n")
          EventMachine.stop
        end

        #publish a message
        publish_message_inline(channel, headers, body)
      end
    end
  end

  it "should receive default ping message with default message template" do
    channel = 'ch_test_default_ping_message_with_default_message_template'
    body = 'body'

    nginx_run_server(config.merge(:subscriber_connection_ttl => nil, :message_template => nil, :header_template => nil, :ping_message_interval => '1s', :ping_message_text => nil), :timeout => 5) do |conf|
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_1.stream do |chunk|
          chunk.should eql("\r\n")
          EventMachine.stop
        end
      end
    end
  end

  it "should receive custom ping message with default message template" do
    channel = 'ch_test_custom_ping_message_with_default_message_template'
    body = 'body'

    nginx_run_server(config.merge(:subscriber_connection_ttl => nil, :message_template => nil, :header_template => nil, :ping_message_interval => '1s', :ping_message_text => "pinging you!!!"), :timeout => 5) do |conf|
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_1.stream do |chunk|
          chunk.should eql("#{conf.ping_message_text}\r\n")
          EventMachine.stop
        end
      end
    end
  end

  it "should receive default ping message with custom message template" do
    channel = 'ch_test_default_ping_message_with_custom_message_template'
    body = 'body'

    nginx_run_server(config.merge(:subscriber_connection_ttl => nil, :message_template => "~id~:~text~", :header_template => nil, :ping_message_interval => '1s', :ping_message_text => nil), :timeout => 5) do |conf|
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_1.stream do |chunk|
          chunk.should eql("-1:\r\n")
          EventMachine.stop
        end
      end
    end
  end

  it "should receive custom ping message with custom message template" do
    channel = 'ch_test_custom_ping_message_with_default_message_template'
    body = 'body'

    nginx_run_server(config.merge(:subscriber_connection_ttl => nil, :message_template => "~id~:~text~", :header_template => nil, :ping_message_interval => '1s', :ping_message_text => "pinging you!!!"), :timeout => 5) do |conf|
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_1.stream do |chunk|
          chunk.should eql("-1:#{conf.ping_message_text}\r\n")
          EventMachine.stop
        end
      end
    end
  end

  it "should receive transfer enconding as 'chunked'" do
    channel = 'ch_test_transfer_encoding_chuncked'

    nginx_run_server(config, :timeout => 5) do |conf|
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_1.stream do |chunk|
          sub_1.response_header['TRANSFER_ENCODING'].should eql("chunked")
          EventMachine.stop
        end
      end
    end
  end

  it "should limit the number of subscribers to one channel" do
    channel = 'ch_test_cannot_add_more_subscriber_to_one_channel_than_allowed'
    other_channel = 'ch_test_cannot_add_more_subscriber_to_one_channel_than_allowed_2'

    nginx_run_server(config.merge(:max_subscribers_per_channel => 3, :subscriber_connection_ttl => "3s"), :timeout => 5) do |conf|
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_2 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_3 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_4 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_4.callback do
          sub_4.response_header.status.should eql(403)
          sub_4.response_header.content_length.should eql(0)
          sub_4.response_header['X_NGINX_PUSHSTREAM_EXPLAIN'].should eql("Subscribers limit per channel has been exceeded.")
        end

        sub_5 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + other_channel.to_s).get :head => headers, :timeout => 30
        sub_5.callback do
          sub_5.response_header.status.should eql(200)
          EventMachine.stop
        end
      end
    end
  end

  it "should accept channels with '.b' in the name" do
    channel = 'room.b18.beautiful'
    response = ''

    nginx_run_server(config.merge(:ping_message_interval => nil, :header_template => nil, :footer_template => nil, :message_template => nil), :timeout => 5) do |conf|
      EventMachine.run do
        publish_message_inline(channel, {'accept' => 'text/html'}, 'msg 1')
        publish_message_inline(channel, {'accept' => 'text/html'}, 'msg 2')
        publish_message_inline(channel, {'accept' => 'text/html'}, 'msg 3')
        publish_message_inline(channel, {'accept' => 'text/html'}, 'msg 4')

        sub = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s + '.b3').get
        sub.stream do |chunk|
          response += chunk
        end
        sub.callback do
          response.should eql("msg 2\r\nmsg 3\r\nmsg 4\r\n")

          response = ''
          sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get
          sub_1.stream do |chunk|
            response += chunk
          end
          sub_1.callback do
            response.should eql("msg 5\r\n")

            EventMachine.stop
          end

          publish_message_inline(channel, {'accept' => 'text/html'}, 'msg 5')
        end
      end
    end
  end

  it "should receive acess control allow headers" do
    channel = 'test_access_control_allow_headers'

    nginx_run_server(config, :timeout => 5) do |conf|
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_1.stream do |chunk|
          sub_1.response_header['ACCESS_CONTROL_ALLOW_ORIGIN'].should eql("*")
          sub_1.response_header['ACCESS_CONTROL_ALLOW_METHODS'].should eql("GET")
          sub_1.response_header['ACCESS_CONTROL_ALLOW_HEADERS'].should eql("If-Modified-Since,If-None-Match")

          EventMachine.stop
        end
      end
    end
  end

  it "should set a default access control allow orgin header" do
    channel = 'test_default_access_control_allow_origin_header'

    nginx_run_server(config, :timeout => 5) do |conf|
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_1.stream do |chunk|
          sub_1.response_header['ACCESS_CONTROL_ALLOW_ORIGIN'].should eql("*")

          EventMachine.stop
        end
      end
    end
  end

  it "should set a custom access control allow orgin header" do
    channel = 'test_custom_access_control_allow_origin_header'

    nginx_run_server(config.merge(:allowed_origins => "custom.domain.com"), :timeout => 5) do |conf|
      EventMachine.run do
        sub_1 = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 30
        sub_1.stream do |chunk|
          sub_1.response_header['ACCESS_CONTROL_ALLOW_ORIGIN'].should eql("custom.domain.com")
          EventMachine.stop
        end
      end
    end
  end

  it "should receive the configured header template" do
    channel = 'ch_test_header_template'

    nginx_run_server(config, :timeout => 5) do |conf|
      EventMachine.run do
        sub = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 60
        sub.stream do |chunk|
          chunk.should eql("#{conf.header_template}\r\n")
          EventMachine.stop
        end
      end
    end
  end

  it "should receive the configured content type" do
    channel = 'ch_test_content_type'

    nginx_run_server(config, :timeout => 5) do |conf|
      EventMachine.run do
        sub = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 60
        sub.stream do |chunk|
          sub.response_header['CONTENT_TYPE'].should eql(conf.content_type)
          EventMachine.stop
        end
      end
    end
  end

  it "should receive ping message on the configured ping message interval" do
    channel = 'ch_test_ping_message_interval'

    step1 = step2 = step3 = step4 = nil
    chunks_received = 0

    nginx_run_server(config.merge(:subscriber_connection_ttl => nil), :timeout => 10) do |conf|
      EventMachine.run do
        sub = EventMachine::HttpRequest.new(nginx_address + '/sub/' + channel.to_s).get :head => headers, :timeout => 60
        sub.stream do |chunk|
          chunks_received += 1;
          step1 = Time.now if chunks_received == 1
          step2 = Time.now if chunks_received == 2
          step3 = Time.now if chunks_received == 3
          step4 = Time.now if chunks_received == 4
          EventMachine.stop if chunks_received == 4
        end
        sub.callback do
          chunks_received.should eql(4)
          time_diff_sec(step2, step1).round.should eql(time_diff_sec(step4, step3).round)
        end
      end
    end
  end
end
