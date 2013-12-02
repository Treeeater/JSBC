require 'CGI'

#DomainOfInterest = ['google-analytics.com','quantserve.com','scorecardresearch.com','googlesyndication.com','optimizely.com','doubleclick.net','serving-sys.com','doubleverify.com','imrworldwide.com','ooyala.com','voicefive.com','grvcdn','gravity.com','chartbeat.com','chartbeat.net','googleapis.com','google.com','olark.com','adroll.com','googletagservices.com','adnxs.com','moatads','axf8.net','msn.com','peer39.net','llnwd.net','wsod.com','dl-rms.com','krxd.net','2mdn.net','cxense.com','bluekai.com','twitter.com']			#put empty here to make it record every request that's not going to host domain.
DomainOfInterest = []			#put empty here to make it record every request that's not going to host domain.
TrustedDomains = ['akamaihd.net','facebook.com']				#put empty here to make everything untrusted.

OnlyDisplayDifferentRequest = true			#Turn on this option and the output HTML file will only contain different/unmatched requests.

if (ARGV.length != 2)
	p "wrong number of arguments. needs 2: 1st: folder 1, 2nd: folder 2"
	exit 
end

userATraces = Array.new
userBTraces = Array.new

Dir.foreach(ARGV[0]) do |item|
	next if item == '.' or item == '..'
	userATraces.push(File.read(ARGV[0]+'/'+item))
end
Dir.foreach(ARGV[1]) do |item|
	next if item == '.' or item == '..'
	userBTraces.push(File.read(ARGV[1]+'/'+item))
end

class Param
	attr_accessor :res, :name, :value
	def initialize(res, name, value)
		@res = res
		@name = name 
		@value = value
	end
	def eq(target_param)
		return (target_param.res == @res && target_param.name == @name && target_param.value == @value)
	end
	def to_s()
		return @res + "\n" + @name + "=" + @value + "\n"
	end
end

class Request
	attr_accessor :protocol, :subdomain, :domain, :resourceURIs, :headers, :postData, :getQueryParams, :getMatrixParams, :originalURL, :cookies
	def initialize(originalURL="", headers="", postData="")
		#set up default value
		@originalURL = originalURL
		@protocol = ""
		@subdomain = ""
		@domain = ""
		@resourceURIs = Array.new			#order matters
		@postData = postData
		@getQueryParams = Hash.new			#Hash inside this Hash. {Resource Name => {parameter name => parameter value}}
		@getMatrixParams = Hash.new
		@cookies = Hash.new
		@headers = (headers == "") ? Hash.new : headers
		
		if (@headers["Cookie"] != nil)
			cookieStr = @headers["Cookie"]
			#right now let's just separate cookies via ';'
			cookieStr.split(';').each{|c|
				if (c.split('=').size==2)
					n = c.split('=')[0]
					v = c.split('=')[1]
					@cookies[n]=v
				end
			}
		end
		
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
			mp1.each_key{|k|
				if (!mp2.has_key?(k) || mp2[k] != mp1[k])
					rv+=1
				end
			}
			mp2.each_key{|k|
				if (!mp1.has_key?(k)) then rv+=1 end
			}
		}
		#headers
		@headers.each_key{|k|
			if (k=="Cookie") then next end		#cookies are handled separately.
			if (!targetReq.headers.has_key?(k) || targetReq.headers[k] != @headers[k]) then rv+=1 end
		}
		targetReq.headers.each_key{|k|
			if (!@headers.has_key?(k)) then rv+=1 end
		}
		#cookies
		@cookies.each_key{
			if (!targetReq.cookies.has_key?(k) || targetReq.cookies[k] != @cookies[k]) then rv+=1 end
		}
		targetReq.cookies.each_key{|k|
			if (!@cookies.has_key?(k)) then rv+=1 end
		}
		if (@postData != targetReq.postData)
			rv+=1
		end
		return rv
	end
	def getResourceString
		return @domain + "/" + @resourceURIs.join("/")
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
		if (@protocol != target_req.protocol) then rv += "<span style='color:red'>#{CGI::escapeHTML(@protocol)}</span><span style='color:blue'>[#{CGI::escapeHTML(target_req.protocol)}]</span>" else rv += "<span style='color:green'>#{CGI::escapeHTML(@protocol)}</span>" end
		if (@subdomain != target_req.subdomain) then rv += "<span style='color:red'>#{CGI::escapeHTML(@subdomain)}</span><span style='color:blue'>[#{CGI::escapeHTML(target_req.subdomain)}]</span>" else rv += "<span style='color:green'>#{CGI::escapeHTML(@subdomain)}</span>" end
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
						rv += "<span style='color:blue'>[Param_Does_Not_Exist!]</span>"
					elsif (target_req.getMatrixParams[res][k] != @getMatrixParams[res][k])
						rv += "<span style='color:green'>#{CGI::escapeHTML(k)}=</span>"
						rv += "<span style='color:red'>#{CGI::escapeHTML(@getMatrixParams[res][k])}</span>"
						rv += "<span style='color:blue'>["
						rv += CGI::escapeHTML(target_req.getMatrixParams[res][k])
						rv += "];</span>"
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
					rv += "<span style='color:blue'>[Param_Does_Not_Exist!]</span>"
				elsif (target_req.getQueryParams[k] != @getQueryParams[k])
					rv += "<span style='color:green'>#{CGI::escapeHTML(k)}=</span>"
					rv += "<span style='color:red'>#{CGI::escapeHTML(@getQueryParams[k])}</span>"
					rv += "<span style='color:blue'>["
					rv += CGI::escapeHTML(target_req.getQueryParams[k])
					rv += "]#{CGI::escapeHTML('&')}</span>"
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
				rv += "<span style='color:blue'>[Header_Does_Not_Exist!]</span>"
			elsif (target_req.headers[k] != @headers[k])
				rv += "<span style='color:green'>#{CGI::escapeHTML(k)}: </span>"
				rv += "<span style='color:red'>#{CGI::escapeHTML(@headers[k])}</span>"
				rv += "<span style='color:blue'>[#{CGI::escapeHTML(target_req.headers[k])}]</span>"
			else
				rv += "<span style='color:green'>"
				rv += CGI::escapeHTML(k + ": " + @headers[k] + ";")
				rv += "</span>"
			end
			rv += "<br/>"
		}
		if (@postData != target_req.postData)
			rv += "<span style='color:red'>#{CGI::escapeHTML(@postData)}</span>"
			rv += "<span style='color:blue'>[#{CGI::escapeHTML(target_req.postData)}]</span>"
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

def identifyCommonReq(traceArray,agreeThres)
	rv = Array.new
	
	#agreeThres can either be a % number or real number
	if (traceArray.size == 0) then return Array.new end
	if (agreeThres <= 0) then return Array.new end
	if (agreeThres < 1) then agreeThres = traceArray.size * agreeThres end
	bigHash = Hash.new			# resourceString => Param name => Param value => occurences
	traceArray.each{|tr|
		tempHash = Hash.new					#used to record if this has already appeared in this trace.
		tr.each{|req|
			if tempHash[req.getResourceString] == nil then tempHash[req.getResourceString] = Hash.new end
			if bigHash[req.getResourceString] == nil then bigHash[req.getResourceString] = Hash.new end
			req.getQueryParams.each_key{|k|
				if tempHash[req.getResourceString]["QP__"+k] == nil then tempHash[req.getResourceString]["QP__"+k] = Hash.new end
				if (tempHash[req.getResourceString]["QP__"+k][req.getQueryParams[k]] == nil)
					tempHash[req.getResourceString]["QP__"+k][req.getQueryParams[k]] = true
				else
					next
				end
				if bigHash[req.getResourceString]["QP__"+k] == nil then bigHash[req.getResourceString]["QP__"+k] = Hash.new end
				if bigHash[req.getResourceString]["QP__"+k][req.getQueryParams[k]] == nil
					bigHash[req.getResourceString]["QP__"+k][req.getQueryParams[k]] = 1
				else
					bigHash[req.getResourceString]["QP__"+k][req.getQueryParams[k]] += 1
				end
			}
			req.resourceURIs.each{|r|
				req.getMatrixParams[r].each_key{|k|
					if tempHash[req.getResourceString]["MP__"+r+"__"+k] == nil then tempHash[req.getResourceString]["MP__"+r+"__"+k] = Hash.new end
					if (tempHash[req.getResourceString]["MP__"+r+"__"+k][req.getMatrixParams[r][k]] == nil)
						tempHash[req.getResourceString]["MP__"+r+"__"+k][req.getMatrixParams[r][k]] = true
					else
						next
					end
					if bigHash[req.getResourceString]["MP__"+r+"__"+k] == nil then bigHash[req.getResourceString]["MP__"+r+"__"+k] = Hash.new end
					if bigHash[req.getResourceString]["MP__"+r+"__"+k][req.getMatrixParams[r][k]] == nil
						bigHash[req.getResourceString]["MP__"+r+"__"+k][req.getMatrixParams[r][k]] = 1
					else
						bigHash[req.getResourceString]["MP__"+r+"__"+k][req.getMatrixParams[r][k]] += 1
					end
				}
			}
			req.headers.each_key{|k|
				if (k=="Cookie") then next end		#cookies are handled separately.
				if tempHash[req.getResourceString]["H__"+k] == nil then tempHash[req.getResourceString]["H__"+k] = Hash.new end
				if (tempHash[req.getResourceString]["H__"+k][req.headers[k]] == nil)
					tempHash[req.getResourceString]["H__"+k][req.headers[k]] = true
				else
					next
				end
				if bigHash[req.getResourceString]["H__"+k] == nil then bigHash[req.getResourceString]["H__"+k] = Hash.new end
				if bigHash[req.getResourceString]["H__"+k][req.headers[k]] == nil
					bigHash[req.getResourceString]["H__"+k][req.headers[k]] = 1
				else
					bigHash[req.getResourceString]["H__"+k][req.headers[k]] += 1
				end
			}
			req.cookies.each_key{|k|
				if tempHash[req.getResourceString]["C__"+k] == nil then tempHash[req.getResourceString]["C__"+k] = Hash.new end
				if (tempHash[req.getResourceString]["C__"+k][req.headers[k]] == nil)
					tempHash[req.getResourceString]["C__"+k][req.headers[k]] = true
				else
					next
				end
				if bigHash[req.getResourceString]["C__"+k] == nil then bigHash[req.getResourceString]["C__"+k] = Hash.new end
				if bigHash[req.getResourceString]["C__"+k][req.cookies[k]] == nil
					bigHash[req.getResourceString]["C__"+k][req.cookies[k]] = 1
				else
					bigHash[req.getResourceString]["C__"+k][req.cookies[k]] += 1
				end
			}
			if req.postData!=""
				if tempHash[req.getResourceString]["POSTData"] == nil then tempHash[req.getResourceString]["POSTData"] = Hash.new end
				if (tempHash[req.getResourceString]["POSTData"][req.postData] == nil)
					tempHash[req.getResourceString]["POSTData"][req.postData] = true
				else
					next
				end
				if bigHash[req.getResourceString]["POSTData"] == nil then bigHash[req.getResourceString]["POSTData"] = Hash.new end
				if bigHash[req.getResourceString]["POSTData"][req.postData] == nil
					bigHash[req.getResourceString]["POSTData"][req.postData] = 1
				else
					bigHash[req.getResourceString]["POSTData"][req.postData] += 1
				end
			end
		}
	}
	bigHash.each_key{|k_res|
		bigHash[k_res].each_key{|k_param_name|
			bigHash[k_res][k_param_name].each_key{|k_param_val|
				if (bigHash[k_res][k_param_name][k_param_val] >= agreeThres)
					rv.push(Param.new(k_res, k_param_name, k_param_val))
				end
			}
		}
	}
	return rv
end

userATraceArray = Array.new
userBTraceArray = Array.new

userATraces.each{|tr|
	strArray = tr.split("\n\n--------------\n\n")
	thisTrace = Array.new
	strArray.each{|str|
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
		if (!DomainOfInterest.empty? && !DomainOfInterest.include?(request.domain)) then next end
		if (!TrustedDomains.empty? && TrustedDomains.include?(request.domain)) then next end
		thisTrace.push(request)
	}
	userATraceArray.push(thisTrace)
}

userBTraces.each{|tr|
	strArray = tr.split("\n\n--------------\n\n")
	thisTrace = Array.new
	strArray.each{|str|
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
		if (!DomainOfInterest.empty? && !DomainOfInterest.include?(request.domain)) then next end
		if (!TrustedDomains.empty? && TrustedDomains.include?(request.domain)) then next end
		thisTrace.push(request)
	}
	userBTraceArray.push(thisTrace)
}

commonReqUserA = identifyCommonReq(userATraceArray,0.9)
commonReqUserB = identifyCommonReq(userBTraceArray,0.9)
commonReqUserA.each{|recA|
	matched = false
	resourceMatched = false						#if resource URL is matched, but not params, this is still set to true.
	commonReqUserB.each_index{|recB_i|
		if (recA.eq(commonReqUserB[recB_i]))
			deleted = commonReqUserB.delete_at(recB_i)
			matched = true
			break
		end
		if (recA.res == commonReqUserB[recB_i].res)
			resourceMatched = true
		end
	}
	if (!matched && resourceMatched)
		print recA.to_s
	end
}