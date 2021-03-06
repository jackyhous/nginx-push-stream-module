module NginxConfiguration
  def self.default_configuration
    {
      :disable_start_stop_server => false,
      :master_process => 'off',
      :daemon => 'off',

      :content_type => 'text/html; charset=utf-8',

      :keepalive => 'off',
      :ping_message_interval => '10s',
      :header_template => %{<html><head><meta http-equiv=\\"Content-Type\\" content=\\"text/html; charset=utf-8\\">\\r\\n<meta http-equiv=\\"Cache-Control\\" content=\\"no-store\\">\\r\\n<meta http-equiv=\\"Cache-Control\\" content=\\"no-cache\\">\\r\\n<meta http-equiv=\\"Expires\\" content=\\"Thu, 1 Jan 1970 00:00:00 GMT\\">\\r\\n<script type=\\"text/javascript\\">\\r\\nwindow.onError = null;\\r\\ndocument.domain = \\'<%= nginx_host %>\\';\\r\\nparent.PushStream.register(this);\\r\\n</script>\\r\\n</head>\\r\\n<body onload=\\"try { parent.PushStream.reset(this) } catch (e) {}\\">},
      :message_template => "<script>p(~id~,'~channel~','~text~');</script>",
      :footer_template => "</body></html>",

      :store_messages => 'on',

      :subscriber_connection_ttl => nil,
      :longpolling_connection_ttl => nil,
      :message_ttl => '50m',

      :max_channel_id_length => 200,
      :max_subscribers_per_channel => nil,
      :max_messages_stored_per_channel => 20,
      :max_number_of_channels => nil,
      :max_number_of_broadcast_channels => nil,

      :broadcast_channel_max_qtd => 3,
      :broadcast_channel_prefix => 'broad_',

      :shared_memory_cleanup_objects_ttl => '5m',

      :subscriber_mode => nil,
      :publisher_mode => nil,
      :padding_by_user_agent => nil,

      :shared_memory_size => '10m',

      :channel_deleted_message_text => nil,
      :ping_message_text => nil,
      :last_received_message_time => nil,
      :last_received_message_tag => nil,
      :user_agent => nil,

      :authorized_channels_only => 'off',
      :allowed_origins => nil,

      :eventsource_support => 'off',

      :client_max_body_size => '32k',
      :client_body_buffer_size => '32k',

      :extra_location => ''
    }
  end


  def self.template_configuration
  %(
pid               <%= pid_file %>;
error_log         <%= error_log %> debug;

# Development Mode
master_process    <%= master_process %>;
daemon            <%= daemon %>;
worker_processes  <%= nginx_workers %>;

events {
  worker_connections  1024;
  use                 <%= (RUBY_PLATFORM =~ /darwin/) ? 'kqueue' : 'epoll' %>;
}

http {
  default_type    application/octet-stream;

  access_log      <%= access_log %>;

  tcp_nopush                      on;
  tcp_nodelay                     on;
  keepalive_timeout               100;
  send_timeout                    10;
  client_body_timeout             10;
  client_header_timeout           10;
  sendfile                        on;
  client_header_buffer_size       1k;
  large_client_header_buffers     2 4k;
  client_max_body_size            1k;
  client_body_buffer_size         1k;
  ignore_invalid_headers          on;
  client_body_in_single_buffer    on;
  client_body_temp_path           <%= client_body_temp %>;

  <%= write_directive("push_stream_ping_message_interval", ping_message_interval, "ping frequency") %>

  <%= write_directive("push_stream_message_template", message_template, "message template") %>

  <%= write_directive("push_stream_subscriber_connection_ttl", subscriber_connection_ttl, "timeout for subscriber connections") %>
  <%= write_directive("push_stream_longpolling_connection_ttl", longpolling_connection_ttl, "timeout for long polling connections") %>
  <%= write_directive("push_stream_header_template", header_template, "header to be sent when receiving new subscriber connection") %>
  <%= write_directive("push_stream_message_ttl", message_ttl, "message ttl") %>
  <%= write_directive("push_stream_footer_template", footer_template, "footer to be sent when finishing subscriber connection") %>

  <%= write_directive("push_stream_max_channel_id_length", max_channel_id_length) %>
  <%= write_directive("push_stream_max_subscribers_per_channel", max_subscribers_per_channel, "max subscribers per channel") %>
  <%= write_directive("push_stream_max_messages_stored_per_channel", max_messages_stored_per_channel, "max messages to store in memory") %>
  <%= write_directive("push_stream_max_number_of_channels", max_number_of_channels) %>
  <%= write_directive("push_stream_max_number_of_broadcast_channels", max_number_of_broadcast_channels) %>

  <%= write_directive("push_stream_broadcast_channel_max_qtd", broadcast_channel_max_qtd) %>
  <%= write_directive("push_stream_broadcast_channel_prefix", broadcast_channel_prefix) %>

  <%= write_directive("push_stream_shared_memory_cleanup_objects_ttl", shared_memory_cleanup_objects_ttl) %>

  <%= write_directive("push_stream_padding_by_user_agent", padding_by_user_agent) %>

  <%= write_directive("push_stream_authorized_channels_only", authorized_channels_only, "subscriber may create channels on demand or only authorized (publisher) may do it?") %>

  <%= write_directive("push_stream_shared_memory_size", shared_memory_size) %>

  <%= write_directive("push_stream_user_agent", user_agent) %>

  <%= write_directive("push_stream_allowed_origins", allowed_origins) %>

  <%= write_directive("push_stream_last_received_message_time", last_received_message_time) %>
  <%= write_directive("push_stream_last_received_message_tag", last_received_message_tag) %>

  <%= write_directive("push_stream_channel_deleted_message_text", channel_deleted_message_text) %>

  <%= write_directive("push_stream_ping_message_text", ping_message_text) %>

  server {
    listen        <%= nginx_port %>;
    server_name   <%= nginx_host %>;

    location /channels-stats {
      # activate channels statistics mode for this location
      push_stream_channels_statistics;

      # query string based channel id
      set $push_stream_channel_id             $arg_id;

      <%= write_directive("push_stream_keepalive", keepalive, "keepalive") %>
    }

    location /pub {
      # activate publisher mode for this location
      push_stream_publisher <%= publisher_mode unless publisher_mode.nil? || publisher_mode == "normal" %>;

      # query string based channel id
      set $push_stream_channel_id             $arg_id;
      <%= write_directive("push_stream_store_messages", store_messages, "store messages") %>
      <%= write_directive("push_stream_keepalive", keepalive, "keepalive") %>

      # client_max_body_size MUST be equal to client_body_buffer_size or
      # you will be sorry.
      client_max_body_size                    <%= client_max_body_size %>;
      client_body_buffer_size                 <%= client_body_buffer_size %>;
    }

    location ~ /sub/(.*)? {
      # activate subscriber mode for this location
      push_stream_subscriber <%= subscriber_mode unless subscriber_mode.nil? || subscriber_mode == "streaming" %>;

      <%= write_directive("push_stream_eventsource_support", eventsource_support, "activate event source support for this location") %>

      # positional channel path
      set $push_stream_channels_path          $1;
      <%= write_directive("push_stream_content_type", content_type, "content-type") %>
      <%= write_directive("push_stream_keepalive", keepalive, "keepalive") %>
    }

    <%= extra_location %>
  }
}
  )
  end
end
