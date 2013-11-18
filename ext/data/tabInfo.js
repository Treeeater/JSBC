self.port.on("reportDomain",function(msg){
		self.port.emit("DomainReport",document.domain);
	}
);

window.addEventListener('beforeunload', function(){
	self.port.emit('clearTrustedDomain', {});
});