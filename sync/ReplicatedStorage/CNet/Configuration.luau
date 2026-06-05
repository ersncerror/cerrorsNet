return {
	BYTES_PER_FRAME = 2048, -- bytes for every frames can send.
	MAX_QUEUED_PACKETS = 128, -- this is for nets if they don't have listeners.
	MAX_CACHE_PACKETS = 64, -- this is for nets if they aren't registered.
	
	DEFAULT_TIMEOUT = 5, -- when net is changed to response, before :WithTimeoutOf call.
}