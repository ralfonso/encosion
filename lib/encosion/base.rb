require 'net/http'
require 'rubygems'
require 'httpclient'
require 'json'

module Encosion
  
  # Generic Encosion error class
  class EncosionError < StandardError
  end
  
  # Raised when there is no token (required to use the Brightcove API)
  class MissingToken < EncosionError
  end
  
  # Raised when some parameter is missing that we need in order to do a search
  class AssetNotFound < EncosionError
  end
  
  # Raised when Brightcove doesn't like the call that was made for whatever reason
  class BrightcoveException < EncosionError
      attr_accessor :code

      def initialize(code=nil)
          self.code = code
      end
  end
  
  # Raised when Brightcove doesn't like the call that was made for whatever reason
  class NoFile < EncosionError
  end
  
  
  # The base for all Encosion objects
  class Base
    
    attr_accessor :read_token, :write_token

    #
    # Class methods
    #
    class << self
      
      # Does a GET to search photos and other good stuff
      def find(*args)
        options = extract_options(args)
        case args.first
        when :all   then find_all(options)
        else        find_from_ids(args,options)
        end
      end
      
        
      # This is an alias for find(:all)
      def all(*args)
        find(:all, *args)
      end
      

      # Performs an HTTP GET
      def get(server,port,secure,path,timeout,command,options)
        http = HTTPClient.new
        http.receive_timeout = timeout
        url = secure ? 'https://' : 'http://'
        url += "#{server}:#{port}#{path}"
        
        options.merge!({'command' => command })
        query_string = options.collect { |key,value| "#{key.to_s}=#{value.to_s}" }.join('&')
        
        response = http.get(url, query_string)

        res_body = response.body.class == String ? response.body : response.body.content
        body = res_body.strip == 'null' ? nil : JSON.parse(res_body.strip)   # if the call returns 'null' then there were no valid results
        header = response.header
        
        error_check(header,body)
        
        # puts "url: #{url}\nquery_string:#{query_string}"

        return body
      end
      
      
      # Performs an HTTP POST
      def post(server,port,secure,path,timeout,command,options,instance)
        http = HTTPClient.new
        http.send_timeout = timeout
        url = secure ? 'https://' : 'http://'
        url += "#{server}:#{port}#{path}"
        
        content = { 'json' => { 'method' => command, 'params' => options }.to_json }    # package up the variables as a JSON-RPC string

        #puts 'pre file content: ' + content.to_json
        content.merge!({ 'file' => instance.file }) if instance.respond_to?('file')             # and add a file if there is one

        response = http.post(url, content)
        # get the header and body for error checking
        res_body = response.body.class == String ? response.body : response.body.content
        body = JSON.parse(res_body.strip)
        header = response.header

        error_check(header,body)
        # if we get here then no exceptions were raised
        return body
      end
      
      
      # Checks the HTTP response and handles any errors
      def error_check(header,body)
        if header.status_code == 200
          return true if body.nil?
          if body['error']
            message = "Brightcove responded with an error: #{body['error']['message']} (code #{body['error']['code']})"
            raise BrightcoveException.new(body['error']['code']), message
          end
        else
          # should only happen if the Brightcove API is unavailable (even BC errors return a 200)
          raise BrightcoveException.new(header.status_code), body + " (status code: #{header.status_code})"
        end
      end
      

      protected
        
        # Pulls any Hash off the end of an array of arguments and returns it
        def extract_options(opts)
          opts.last.is_a?(::Hash) ? opts.pop : {}
        end


        # Find an asset from a single or array of ids
        def find_from_ids(ids, options)
          expects_array = ids.first.kind_of?(Array)
          return ids.first if expects_array && ids.first.empty?

          ids = ids.flatten.compact.uniq

          case ids.size
            when 0
              raise AssetNotFound, "Couldn't find #{self.class} without an ID"
            when 1
              result = find_one(ids.first, options)
              expects_array ? [ result ] : result
            else
              find_some(ids, options)
          end
        end
        

        # Turns a hash into a query string and appends the token
        def queryize_args(args, type)
          case type
          when :read
            raise MissingToken, 'No read token found' if @read_token.nil?
            args.merge!({ :token => @read_token })
          when :write
            raise MissingToken, 'No write token found' if @write_token.nil?
            args.merge!({ :token => @write_token })
          end
          return args.collect { |key,value| "#{key.to_s}=#{value.to_s}" }.join('&')
        end
      
    end
    
    
  end
  
end
