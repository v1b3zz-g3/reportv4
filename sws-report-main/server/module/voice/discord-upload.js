;(function() {
    const https = require('https');

    /**
     * Sanitize username for safe filename usage
     * @param {string} name - Raw username
     * @returns {string} - Sanitized filename-safe name
     */
    function sanitizeFilename(name) {
        if (!name || typeof name !== 'string') return 'unknown';
        
        return name
            .toLowerCase()
            .replace(/[^a-z0-9_-]/g, '_') // Replace invalid chars
            .replace(/_+/g, '_') // Collapse multiple underscores
            .replace(/^[_-]+/, '') // Remove leading
            .replace(/[_-]+$/, '') // Remove trailing
            .substring(0, 32) || 'user'; // Limit length with fallback
    }

    /**
     * Upload audio to Discord webhook via multipart/form-data
     */
    function uploadToDiscord(data, callback) {
        let params = data;
        if (typeof data === 'number') {
            params = callback;
            callback = arguments[2];
        }

        const { webhookUrl, threadId, base64Audio, reportId, senderName, botName, botAvatar } = params || {};

        console.log('[sws-report:voice] Upload request:', {
            hasWebhook: !!webhookUrl,
            hasThread: !!threadId,
            hasAudio: !!base64Audio,
            reportId,
            senderName,
            audioLength: base64Audio?.length
        });

        if (!webhookUrl || !base64Audio) {
            if (callback) callback(false, null, 'Missing webhookUrl or base64Audio');
            return;
        }

        if (!threadId) {
            console.error('[sws-report:voice] ERROR: Missing threadId for report #' + reportId);
            console.error('[sws-report:voice] Thread must be created before uploading voice message');
            if (callback) callback(false, null, 'Missing threadId - report thread must exist first');
            return;
        }

        try {
            const audioBuffer = Buffer.from(base64Audio, 'base64');

            if (audioBuffer.length === 0) {
                if (callback) callback(false, null, 'Empty audio data');
                return;
            }

            const boundary = '----WebKitFormBoundary' + Math.random().toString(36).substring(2);
            const timestamp = new Date().toISOString().replace(/[-:T.Z]/g, '').substring(0, 14);
            
            // CRITICAL FIX: Sanitize sender name for filename
            const safeName = sanitizeFilename(senderName || 'unknown');
            const filename = `voice_r${reportId}_${safeName}_${timestamp}.webm`;

            console.log('[sws-report:voice] Generated filename:', filename);

            const payloadJson = {
                username: botName || 'Report System',
                content: `🎤 Voice message in Report #${reportId} from ${senderName || 'Unknown'}`
            };
            if (botAvatar) {
                payloadJson.avatar_url = botAvatar;
            }

            const bodyParts = [];
            
            bodyParts.push(Buffer.from(
                `--${boundary}\r\n` +
                'Content-Disposition: form-data; name="payload_json"\r\n' +
                'Content-Type: application/json\r\n\r\n' +
                JSON.stringify(payloadJson) + '\r\n'
            ));
            
            bodyParts.push(Buffer.from(
                `--${boundary}\r\n` +
                `Content-Disposition: form-data; name="file"; filename="${filename}"\r\n` +
                'Content-Type: audio/webm\r\n\r\n'
            ));
            
            bodyParts.push(audioBuffer);
            bodyParts.push(Buffer.from(`\r\n--${boundary}--\r\n`));

            const fullBody = Buffer.concat(bodyParts);

            const url = new URL(`${webhookUrl}?wait=true&thread_id=${threadId}`);

            console.log('[sws-report:voice] Uploading to thread:', threadId);

            const options = {
                hostname: url.hostname,
                path: url.pathname + url.search,
                method: 'POST',
                headers: {
                    'Content-Type': `multipart/form-data; boundary=${boundary}`,
                    'Content-Length': fullBody.length
                }
            };

            const req = https.request(options, (res) => {
                let responseData = '';
                res.on('data', chunk => responseData += chunk);
                res.on('end', () => {
                    console.log('[sws-report:voice] Discord response status:', res.statusCode);
                    
                    if (res.statusCode === 200) {
                        try {
                            const json = JSON.parse(responseData);
                            if (json.attachments?.[0]?.url) {
                                console.log('[sws-report:voice] Upload successful');
                                callback(true, json.attachments[0].url, null);
                            } else {
                                console.error('[sws-report:voice] No attachment URL in response');
                                callback(false, null, 'No attachment URL in response');
                            }
                        } catch (e) {
                            console.error('[sws-report:voice] Failed to parse response:', e.message);
                            callback(false, null, 'Failed to parse Discord response');
                        }
                    } else {
                        let errorMsg = `HTTP ${res.statusCode}`;
                        try {
                            const errorData = JSON.parse(responseData);
                            errorMsg = errorData.message || JSON.stringify(errorData);
                        } catch {
                            if (responseData) errorMsg = responseData;
                        }
                        console.error('[sws-report:voice] Upload failed:', errorMsg);
                        callback(false, null, errorMsg);
                    }
                });
            });

            req.on('error', (e) => {
                console.error('[sws-report:voice] Request error:', e.message);
                callback(false, null, e.message);
            });
            
            req.write(fullBody);
            req.end();

        } catch (e) {
            console.error('[sws-report:voice] Exception:', e.message);
            if (callback) callback(false, null, e.message);
        }
    }

    exports('uploadVoiceToDiscord', uploadToDiscord);
})();