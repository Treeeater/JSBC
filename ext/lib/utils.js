const {Cc,Ci,Cr} = require("chrome");
var file = require("file");
var tabs = require("sdk/tabs");
//var profilePath = require("system").pathFor("ProfD");
var fileComponent = Cc["@mozilla.org/file/local;1"].createInstance(Ci.nsILocalFile);
var cookieService = Cc["@mozilla.org/cookiemanager;1"].getService(Ci.nsICookieManager2);
var trustedDomains = [];
var rootOutputPath = "D:\\Research\\JSBC\\results\\";
var fileNameToStoreTraffic = "";

function fileNameSanitize(str)
{
	return str.replace(/[^a-zA-Z0-9\.]*/g,"").substr(0,32);
}

function getTLDFromDomain(domain)
{
	var temp = domain.split('.');
	if (temp.length <= 2) return domain;
	else return temp[temp.length-2] + '.' + temp[temp.length-1];
}

tabs.on('open', function onOpen(tab) {
	tab.i = tabs.length;
});

function closeAllOtherTabs(){
	if (tabs.length <= 1) return;
	for each (var tabIterator in tabs){
		if (tabIterator.i != 1) tabIterator.close();
	}
}

function closeAllTabs(){
	for each (var tabIterator in tabs){
		tabIterator.close();
	}
}

function navigateFirstTab(url){
	trustedDomains.push(getTLDFromURL(url));
	tabs[0].url = url;
	fileNameToStoreTraffic = rootOutputPath + fileNameSanitize(url);
	if (!file.exists(fileNameToStoreTraffic)) {
		file.mkpath(fileNameToStoreTraffic);
		fileNameToStoreTraffic = fileNameToStoreTraffic + "\\1.txt";
	}
	else {
		var i = 1;
		while (file.exists(fileNameToStoreTraffic + "\\" + i.toString() + ".txt"))
		{
			i++;
		}
		fileNameToStoreTraffic = fileNameToStoreTraffic + "\\" + i.toString() + ".txt";
	}
}
function deleteCookies()
{
	cookieService.removeAll();
}

function getTLDFromURL(URL)
{
	var temp = URL.split('/');
	if (temp.length <= 2) return "";
	temp = temp[2];
	if (temp.indexOf(':')!=-1) temp = temp.substr(0,temp.indexOf(':'));
	return getTLDFromDomain(temp);
}

exports.saveToFile = function(content, fileName)
{
	if (fileName) {
		fileName = fileNameSanitize(fileName)+".txt";
		fileComponent.initWithPath(rootOutputPath+fileName);  // The path passed to initWithPath() should be in "native" form.
	}
	else {
		if (fileNameToStoreTraffic == "") {
			console.log("Error: fileNameToStoreTraffic not initialized!!!");
			return;
		}
		fileComponent.initWithPath(fileNameToStoreTraffic);  // The path passed to initWithPath() should be in "native" form.
	}
	var foStream = Cc["@mozilla.org/network/file-output-stream;1"].createInstance(Ci.nsIFileOutputStream);
	foStream.init(fileComponent, 0x02 | 0x08 | 0x10, 0666, 0); 
	foStream.write(content+"\n", content.length+1);
	foStream.close();
}

exports.getTLDFromDomain = getTLDFromDomain;
exports.getTLDFromURL = getTLDFromURL;
exports.closeAllOtherTabs = closeAllOtherTabs;
exports.closeAllTabs = closeAllTabs;
exports.navigateFirstTab = navigateFirstTab;
exports.deleteCookies = deleteCookies;
exports.getTrustedDomains = function(){return trustedDomains;};