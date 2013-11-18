require 'CGI'

if (ARGV.length != 2)
	p "wrong number of arguments. needs 2."
	exit 
end

src1Str = File.read(ARGV[0])
src2Str = File.read(ARGV[1])

class Request
	attr_accessor :protocol, :subdomain, :domain, :resourceURIs, :headers, :postData, :getQueryParams, :getMatrixParams
	def initialize(originalURL="", headers="", postData="")
		#set up default value
		@protocol = ""
		@subdomain = ""
		@domain = ""
		@resourceURIs = Array.new			#order matters
		@headers = headers
		@postData = postData
		@getQueryParams = Hash.new			#Hash inside this Hash. {Resource Name => {parameter name => parameter value}}
		@getMatrixParams = Hash.new
		
		if (originalURL == "")
			#empty init.
			return
		end
		
		#parse the URI
		remainingURL = originalURL
		@protocol = remainingURL[0..remainingURL.index('/')+1]		#assume protocol always has ://
		remainingURL = remainingURL[remainingURL.index('/')+2..-1]
		if (!remainingURL.index('/'))		
			#root dir access.
			@domain = remainingURL.split('.')[-2..-1].join(".")
			@subdomain = remainingURL[0..-@domain.length-1]
			return
		end
		domain = remainingURL[0..remainingURL.index('/')-1]
		@domain = domain.split('.')[-2..-1].join(".")
		@subdomain = domain[0..-@domain.length-1]
		remainingURL = remainingURL[remainingURL.index('/')+1..-1]
		#left with everything to the right of domain.
		if (remainingURL.index('?'))
			#retrieve query parameters, according to spec the always appear at the end.
			@getQueryParams = extractGetQueryParams(originalURL)
			remainingURL = remainingURL[0..remainingURL.index('?')-1]
		end
		#now we are left with only the middle section of the URL: resources path and their (potential) matrix parameters.
		remainingURL.split('/').each{|resource|
			matrixParams = Hash.new
			resourceURI = resource
			if (resource.index(';'))
				#has matrix param
				resourceURI = resource[0..resource.index(';')-1]
				resource[resource.index(';')+1..-1].split(';').each{|item|
					if (item.index("="))
						name = item[0..item.index("=")-1]
						value = item[name.size+1..-1]
						matrixParams[name] = value
					else
						matrixParams[item] = ""
					end
				}
			end
			@resourceURIs.push(resourceURI)
			@getMatrixParams[resourceURI] = matrixParams
		}
	end
	def extractGetQueryParams(url)
		#assume the get query params are standard, using ? and &
		#there's going to be no # in the url, since it's captured by firefox addon
		rv = Hash.new
		stringArr = url[url.index('?')+1..-1].split('&')
		stringArr.each{|item|
			if (item.index("="))
				name = item[0..item.index("=")-1]
				value = item[name.size+1..-1]
				rv[name] = value
			else
				rv[item] = ""
			end
		}
		return rv
	end
	def compareDiffScore(targetReq)
		rv = 0
		if (@domain != targetReq.domain) then return 9999 end				#domain doesn't match - impossible for these two requests to match.
		if (@resourceURIs.join("/") != targetReq.resourceURIs.join("/")) then return 9999 end		#resources doesn't match, means URI doesn't match.
		if (@subdomain != targetReq.subdomain)
			#subdomain doesn't match but the rest URI matches sometimes means CDN dynamically allocate different nodes to handle requests.
			rv+=1
		end				
		#Query params
		@getQueryParams.each_key{|k|
			if (!targetReq.getQueryParams.has_key?(k) || targetReq.getQueryParams[k] != @getQueryParams[k]) then rv+=1 end
		}
		targetReq.getQueryParams.each_key{|k|
			if (!@getQueryParams.has_key?(k)) then rv+=1 end
		}
		#Matrix params
		@resourceURIs.each{|res|
			mp1 = @getMatrixParams[res]
			mp2 = targetReq.getMatrixParams[res]
			mp1.each{|k|
				if (!mp2.has_key?(k) || mp2[k] != mp1[k]) then rv+=1 end
			}
			mp2.each{|k|
				if (!mp1.has_key?(k)) then rv+=1 end
			}
		}
		#headers
		@headers.each_key{|k|
			if (!targetReq.headers.has_key?(k) || targetReq.headers[k] != @headers[k]) then rv+=1 end
		}
		targetReq.headers.each_key{|k|
			if (!@headers.has_key?(k)) then rv+=1 end
		}
		if (@postData != targetReq.postData)
			rv+=1
		end
		return rv
	end
	def serialize
		rv = @protocol + @subdomain + @domain
		@resourceURIs.each{|res|
			rv += ("/"+res)
			if !@getMatrixParams[res].empty?
				rv += ";"
				@getMatrixParams[res].each_key{|k| rv += (k + "=" + @getMatrixParams[res][k] + ";")}
				rv = rv[0..-2]		#get rid of the last;
			end
		}
		if !@getQueryParams.empty?
			rv += "?" 
			@getQueryParams.each_key{|k| rv += (k + "=" + @getQueryParams[k] + "&")}
			rv = rv[0..-2]		#get rid of the last &
		end
		rv += "\n"
		@headers.each_key{|k| rv += (k + ": " + @headers[k] + "\n")}
		rv += @postData
		return rv
	end
	def generateDiffHTML(target_req)
		#target_req is already confirmed to be matching this request.
		rv = ""
		if (@protocol != target_req.protocol) then rv += "<span style='color:red'>#{CGI::escapeHTML(@protocol)}</span>" else rv += "<span style='color:green'>#{CGI::escapeHTML(@protocol)}</span>" end
		if (@subdomain != target_req.subdomain) then rv += "<span style='color:red'>#{CGI::escapeHTML(@subdomain)}</span>" else rv += "<span style='color:green'>#{CGI::escapeHTML(@subdomain)}</span>" end
		rv += "<span style='color:green'>#{CGI::escapeHTML(@domain)}</span>"
		@resourceURIs.each{|res|
			rv += "<span style='color:green'>/#{CGI::escapeHTML(res)}</span>"
			if !@getMatrixParams[res].empty?
				rv += ";"
				@getMatrixParams[res].each_key{|k|
					if !target_req.getMatrixParams[res].has_key?(k)
						rv += "<span style='color:red'>"
						rv += CGI::escapeHTML(k + "=" + @getMatrixParams[res][k] + ";")
						rv += "</span>"
					elsif (target_req.getMatrixParams[res][k] != @getMatrixParams[res][k])
						rv += "<span style='color:green'>#{CGI::escapeHTML(k)}=</span>"
						rv += "<span style='color:red'>#{CGI::escapeHTML(@getMatrixParams[res][k]+";")}</span>"
					else
						rv += "<span style='color:green'>"
						rv += CGI::escapeHTML(k + "=" + @getMatrixParams[res][k] + ";")
						rv += "</span>"
					end
				}
				rv = rv[0..-9] + rv[-7..-1]		#get rid of the last;
			end
		}
		if !@getQueryParams.empty?
			rv += "?" 
			@getQueryParams.each_key{|k|
				if !target_req.getQueryParams.has_key?(k)
					rv += "<span style='color:red'>"
					rv += CGI::escapeHTML(k + "=" + @getQueryParams[k] + "&")
					rv += "</span>"
				elsif (target_req.getQueryParams[k] != @getQueryParams[k])
					rv += "<span style='color:green'>#{CGI::escapeHTML(k)}=</span>"
					rv += "<span style='color:red'>#{CGI::escapeHTML(@getQueryParams[k]+"&")}</span>"
				else
					rv += "<span style='color:green'>"
					rv += CGI::escapeHTML(k + "=" + @getQueryParams[k] + "&")
					rv += "</span>"
				end
			}
			rv = rv[0..-13] + rv[-7..-1]		#get rid of the last &
		end
		rv += "<br/>"
		@headers.each_key{|k|
			if !target_req.headers.has_key?(k)
				rv += "<span style='color:red'>"
				rv += CGI::escapeHTML(k + ": " + @headers[k] + ";")
				rv += "</span>"
			elsif (target_req.headers[k] != @headers[k])
				rv += "<span style='color:green'>#{CGI::escapeHTML(k)}: </span>"
				rv += "<span style='color:red'>#{CGI::escapeHTML(@headers[k])}</span>"
			else
				rv += "<span style='color:green'>"
				rv += CGI::escapeHTML(k + ": " + @headers[k] + ";")
				rv += "</span>"
			end
			rv += "<br/>"
		}
		if (@postData != target_req.postData)
			rv += "<span style='color:red'>#{CGI::escapeHTML(@postData)}</span>"
		else
			rv += "<span style='color:green'>#{CGI::escapeHTML(@postData)}</span>"
		end
	end
	def to_html
		#get itself ready for a plain style HTML output
		rv = @protocol + @subdomain + @domain
		@resourceURIs.each{|res|
			rv += ("/"+res)
			if !@getMatrixParams[res].empty?
				rv += ";"
				@getMatrixParams[res].each_key{|k| rv += (k + "=" + @getMatrixParams[res][k] + ";")}
				rv = rv[0..-2]		#get rid of the last;
			end
		}
		if !@getQueryParams.empty?
			rv += "?" 
			@getQueryParams.each_key{|k| rv += (k + "=" + @getQueryParams[k] + "&")}
			rv = rv[0..-2]		#get rid of the last &
		end
		rv = CGI::escapeHTML(rv)
		rv += "<br/>"
		@headers.each_key{|k| rv += (CGI::escapeHTML(k + ": " + @headers[k]) + "<br/>")}
		rv += CGI::escapeHTML(@postData)
		return rv
	end
end

src1StrArray = src1Str.split("\n\n--------------\n\n")
src2StrArray = src2Str.split("\n\n--------------\n\n")
src1ReqArray = Array.new
src2ReqArray = Array.new

src1StrArray.each{|str|
	url = str[0..str.index("\n")-1]
	str = str[url.length+1..-1]
	headers = Hash.new
	headerStr = str
	postData = ""
	if (str.index('JSBC_POSTDATA:'))
		headerStr = str[0..str.index('JSBC_POSTDATA:')-1]
		postData = str[str.index('JSBC_POSTDATA:')..-1]
	end
	headerStr.split("\n").each{|h|		#we are assuming the header contents don't contain \n themselves.
		if (h.index(":"))
			name = h[0..h.index(":")-1]
			if (name == "Referer") then next end			#ignore referer header differences, we are look into 3rd p script leaking information proactively, not passively.
			value = h[name.size+2..-1]
			headers[name] = value
		else
			headers[h] = ""
		end
	}
	request = Request.new(url,headers,postData)
	src1ReqArray.push(request)
}

src2StrArray.each{|str|
	url = str[0..str.index("\n")-1]
	str = str[url.length+1..-1]
	headers = Hash.new
	headerStr = str
	postData = ""
	if (str.index('JSBC_POSTDATA:'))
		headerStr = str[0..str.index('JSBC_POSTDATA:')-1]
		postData = str[str.index('JSBC_POSTDATA:')..-1]
	end
	headerStr.split("\n").each{|h|
		if (h.index(":"))
			name = h[0..h.index(":")-1]
			if (name == "Referer") then next end			#ignore referer header differences, we are look into 3rd p script leaking information proactively, not passively.
			value = h[name.size+2..-1]
			headers[name] = value
		else
			headers[h] = ""
		end
	}
	request = Request.new(url,headers,postData)
	src2ReqArray.push(request)
}

identicalRequests = Array.new
matchedRequests1 = Array.new
matchedRequests2 = Array.new
unmatchedRequests = Array.new
htmlStringOutput = "<html><body>"
src1ReqArray.each{|req1|
	match_req = Request.new
	min_diff = 9999
	src2ReqArray.each{|req2|
		diff = req1.compareDiffScore(req2)
		if (diff < min_diff)
			match_req = req2
			min_diff = diff
		end
	}
	if (min_diff == 9999)
		unmatchedRequests.push(req1)
		htmlStringOutput += "<div style='color:red'>"
		htmlStringOutput += req1.to_html
		htmlStringOutput += "</div><br/>"
	elsif (min_diff < 9999 && min_diff > 0)
		matchedRequests1.push(req1)
		matchedRequests2.push(match_req)
		src2ReqArray.delete(match_req)
		htmlStringOutput += "<div>"+req1.generateDiffHTML(match_req)+"</div><br/>"
	elsif (min_diff==0)
		src2ReqArray.delete(match_req)
		htmlStringOutput += "<div style='color:green'>"
		htmlStringOutput += req1.to_html
		htmlStringOutput += "</div><br/>"
		identicalRequests.push(req1)
	end
}
htmlStringOutput += "</body></html>"
#p matchedRequests.map{|m| m.serialize}.join("\n")
p "T1: " + src1ReqArray.size.to_s
p "U1: " + unmatchedRequests.size.to_s
p "T2: " + (src2ReqArray.size + matchedRequests1.size + identicalRequests.size).to_s
p "U2: " + src2ReqArray.size.to_s
p "M: " + matchedRequests1.size.to_s
p "I: " + identicalRequests.size.to_s
File.open("M1.txt","w+"){|f| f.write(matchedRequests1.map{|m| m.serialize}.join("\n"))}
File.open("U1.txt","w+"){|f| f.write(unmatchedRequests.map{|m| m.serialize}.join("\n"))}
File.open("M2.txt","w+"){|f| f.write(matchedRequests2.map{|m| m.serialize}.join("\n"))}
File.open("U2.txt","w+"){|f| f.write(src2ReqArray.map{|m| m.serialize}.join("\n"))}
File.open("1.html","w+"){|f| f.write(htmlStringOutput)}