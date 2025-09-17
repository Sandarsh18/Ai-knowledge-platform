import React, { useState } from 'react';

export default function Chat() {
  const [docId, setDocId] = useState('');
  const [question, setQuestion] = useState('');
  const [error, setError] = useState('');
  const [loading, setLoading] = useState(false);
  const [retryAttempt, setRetryAttempt] = useState(0);
  const [chatHistory, setChatHistory] = useState([]);

  // Helper function for exponential backoff retry
  const sleep = (ms) => new Promise(resolve => setTimeout(resolve, ms));
  
  const makeApiRequest = async (url, options, maxRetries = 3) => {
    for (let attempt = 0; attempt < maxRetries; attempt++) {
      setRetryAttempt(attempt + 1);
      
      try {
        const response = await fetch(url, options);
        const data = await response.json();
        
        // Handle specific error codes
        if (response.status === 429) {
          // Quota exceeded - don't retry, show user-friendly message
          throw new Error('QUOTA_EXCEEDED');
        }
        
        if (response.status === 502 || response.status === 503 || response.status === 504) {
          // Server/gateway errors - retry with exponential backoff
          if (attempt < maxRetries - 1) {
            const delay = Math.pow(2, attempt) * 1000; // 1s, 2s, 4s...
            await sleep(delay);
            continue;
          }
        }
        
        if (response.status === 500 && attempt < maxRetries - 1) {
          // Internal server error - retry with exponential backoff
          const delay = Math.pow(2, attempt) * 1000; // 1s, 2s, 4s...
          await sleep(delay);
          continue;
        }
        
        if (!response.ok) {
          // Pass through the backend error message
          const errorMessage = data.error || `HTTP ${response.status}: ${response.statusText}`;
          const errorObj = new Error(errorMessage);
          errorObj.statusCode = response.status;
          errorObj.errorType = data.error_type || 'UNKNOWN_ERROR';
          throw errorObj;
        }
        
        return { success: true, data };
        
      } catch (error) {
        if (error.message === 'QUOTA_EXCEEDED') {
          throw error; // Don't retry quota errors
        }
        
        if (attempt === maxRetries - 1) {
          // Last attempt failed
          throw error;
        }
        
        // Network error - retry with exponential backoff
        const delay = Math.pow(2, attempt) * 1000;
        await sleep(delay);
      }
    }
  };

  const handleAsk = async (e) => {
    e.preventDefault();
    if (!question.trim()) return;
    
    setLoading(true);
    setError('');
    setRetryAttempt(0);
    
    // Add user question to chat history
    const userMessage = { type: 'user', content: question, timestamp: new Date() };
    setChatHistory(prev => [...prev, userMessage]);
    
    const token = localStorage.getItem('token');
    
    // Doc_id correction system for handling upload/display mismatches
    let correctedDocId = docId;
    const knownDocIdMappings = {
      '31c3fea0-1baf-43a1-823e-6070e6ef6088': '31c3fab0-1baf-41a1-837d-687bf6bfdd88'
    };
    
    // Auto-correction for known mappings
    if (knownDocIdMappings[docId]) {
      correctedDocId = knownDocIdMappings[docId];
      console.log('Applied known doc_id correction:', docId, '->', correctedDocId);
      
      // Show user a warning about the correction
      const correctionMessage = { 
        type: 'ai', 
        content: `📝 Auto-correction applied: Document ID mismatch detected and fixed. Using: ${correctedDocId.substring(0, 8)}...`, 
        timestamp: new Date(),
        isInfo: true 
      };
      setChatHistory(prev => [...prev, correctionMessage]);
    }
    
    try {
      const result = await makeApiRequest(
        process.env.REACT_APP_API_URL + '/query',
        {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            'Authorization': token,
          },
          body: JSON.stringify({ doc_id: correctedDocId, question }),
        }
      );
      
      // Handle server-side doc_id correction notification
      if (result.data.doc_id_corrected) {
        const serverCorrectionMessage = { 
          type: 'ai', 
          content: `🔧 Server correction: ${result.data.correction_message}`, 
          timestamp: new Date(),
          isInfo: true 
        };
        setChatHistory(prev => [...prev, serverCorrectionMessage]);
        
        // Update the docId state to the corrected one for future queries
        setDocId(result.data.corrected_doc_id);
        console.log('Server applied doc_id correction:', result.data.original_doc_id, '->', result.data.corrected_doc_id);
      }
      
      // Add AI response to chat history
      const aiMessage = { 
        type: 'ai', 
        content: result.data.answer, 
        timestamp: new Date(),
        isFallback: result.data.is_fallback || false
      };
      setChatHistory(prev => [...prev, aiMessage]);
      
    } catch (err) {
      let errorMessage;
      let canRetry = true;
      
      // Handle structured errors from backend
      if (err.message === 'QUOTA_EXCEEDED' || err.errorType === 'QUOTA_EXCEEDED') {
        errorMessage = '⚠️ API quota exceeded. Please try again later or contact support if this persists.';
        canRetry = false;
      } else if (err.statusCode === 429) {
        errorMessage = '⚠️ Too many requests. Please wait a moment before trying again.';
        canRetry = false;
      } else if (err.statusCode === 404) {
        errorMessage = '📄 Document not found. Please check your document ID or re-upload the document.';
        canRetry = false;
      } else if (err.statusCode === 502 || err.statusCode === 503 || err.statusCode === 504) {
        errorMessage = '🔧 AI service temporarily unavailable. We tried multiple times but couldn\'t connect.';
      } else if (err.statusCode === 500) {
        errorMessage = '🔧 Server error occurred. We tried multiple times but couldn\'t complete your request.';
      } else if (err.message.includes('NetworkError') || err.name === 'TypeError') {
        errorMessage = '🌐 Network connection error. Please check your internet connection and try again.';
      } else {
        // Use the backend error message if available, otherwise fallback
        errorMessage = `❌ ${err.message || 'An unexpected error occurred. Please try again.'}`;
      }
      
      // Add error message to chat history instead of just setting error state
      const errorChatMessage = { 
        type: 'ai', 
        content: errorMessage + (canRetry ? '\n\n💡 Tip: You can try sending your question again.' : ''), 
        timestamp: new Date(),
        isError: true 
      };
      setChatHistory(prev => [...prev, errorChatMessage]);
      setError(errorMessage);
    }
    
    setLoading(false);
    setRetryAttempt(0);
    setQuestion(''); // Clear input after sending
  };

  const clearChat = () => {
    setChatHistory([]);
    setError('');
  };

  return (
    <div style={{
      minHeight: '100vh',
      background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
      padding: '20px'
    }}>
      <div style={{
        maxWidth: '900px',
        margin: '0 auto',
        background: 'white',
        borderRadius: '16px',
        boxShadow: '0 20px 40px rgba(0,0,0,0.1)',
        overflow: 'hidden',
        display: 'flex',
        flexDirection: 'column',
        height: '90vh'
      }}>
        {/* Header */}
        <div style={{
          background: 'linear-gradient(135deg, #667eea, #764ba2)',
          color: 'white',
          padding: '20px 30px',
          display: 'flex',
          alignItems: 'center',
          justifyContent: 'space-between'
        }}>
          <div>
            <h1 style={{
              margin: '0 0 5px 0',
              fontSize: '24px',
              fontWeight: '700'
            }}>
              🤖 AI Document Chat
            </h1>
            <p style={{
              margin: '0',
              fontSize: '14px',
              opacity: '0.9'
            }}>
              Ask questions about your uploaded documents
            </p>
          </div>
          <button
            onClick={clearChat}
            style={{
              background: 'rgba(255,255,255,0.2)',
              border: 'none',
              color: 'white',
              padding: '8px 16px',
              borderRadius: '8px',
              cursor: 'pointer',
              fontSize: '12px',
              fontWeight: '600',
              transition: 'all 0.3s ease'
            }}
            onMouseEnter={(e) => {
              e.target.style.background = 'rgba(255,255,255,0.3)';
            }}
            onMouseLeave={(e) => {
              e.target.style.background = 'rgba(255,255,255,0.2)';
            }}
          >
            🗑️ Clear Chat
          </button>
        </div>

        {/* Document ID Input */}
        <div style={{
          padding: '20px 30px',
          borderBottom: '1px solid #e5e7eb',
          backgroundColor: '#f8fafc'
        }}>
          <label style={{
            display: 'block',
            marginBottom: '8px',
            fontSize: '14px',
            fontWeight: '600',
            color: '#374151'
          }}>
            Document ID
          </label>
          <input
            type="text"
            value={docId}
            onChange={e => setDocId(e.target.value)}
            placeholder="Enter document ID (e.g., 69eee061-9574-446a-8ee4-cbaf7463b534)"
            required
            style={{
              width: '100%',
              padding: '12px 16px',
              border: '2px solid #e5e7eb',
              borderRadius: '10px',
              fontSize: '14px',
              fontFamily: 'monospace',
              transition: 'all 0.3s ease',
              outline: 'none',
              boxSizing: 'border-box'
            }}
            onFocus={(e) => {
              e.target.style.borderColor = '#667eea';
              e.target.style.boxShadow = '0 0 0 3px rgba(102, 126, 234, 0.1)';
            }}
            onBlur={(e) => {
              e.target.style.borderColor = '#e5e7eb';
              e.target.style.boxShadow = 'none';
            }}
          />
        </div>

        {/* Chat Messages */}
        <div style={{
          flex: '1',
          padding: '20px 30px',
          overflowY: 'auto',
          backgroundColor: '#fafafa'
        }}>
          {chatHistory.length === 0 ? (
            <div style={{
              textAlign: 'center',
              padding: '60px 20px',
              color: '#6b7280'
            }}>
              <div style={{ fontSize: '48px', marginBottom: '16px' }}>💬</div>
              <h3 style={{ margin: '0 0 8px 0', color: '#374151' }}>Start a Conversation</h3>
              <p style={{ margin: '0', fontSize: '14px' }}>
                Enter a document ID and ask your first question to get started
              </p>
            </div>
          ) : (
            <div style={{ display: 'flex', flexDirection: 'column', gap: '16px' }}>
              {chatHistory.map((message, index) => (
                <div
                  key={index}
                  style={{
                    display: 'flex',
                    justifyContent: message.type === 'user' ? 'flex-end' : 'flex-start'
                  }}
                >
                  <div style={{
                    maxWidth: '70%',
                    padding: '12px 16px',
                    borderRadius: message.type === 'user' ? '18px 18px 4px 18px' : '18px 18px 18px 4px',
                    background: message.type === 'user' 
                      ? 'linear-gradient(135deg, #667eea, #764ba2)'
                      : message.isError 
                        ? '#fef2f2' // Light red background for errors
                        : message.isFallback
                          ? '#fffbeb' // Light amber background for fallback responses
                          : message.isInfo
                            ? '#f0f9ff' // Light blue background for info messages
                            : 'white',
                    color: message.type === 'user' 
                      ? 'white' 
                      : message.isError 
                        ? '#dc2626' // Red text for errors
                        : message.isFallback
                          ? '#92400e' // Amber text for fallback
                          : message.isInfo
                            ? '#1e40af' // Blue text for info
                            : '#374151',
                    border: message.isError 
                      ? '1px solid #fecaca' 
                      : message.isFallback 
                        ? '1px solid #fed7aa'
                        : message.isInfo
                          ? '1px solid #bfdbfe' // Blue border for info
                          : 'none',
                    boxShadow: '0 2px 8px rgba(0,0,0,0.1)',
                    fontSize: '14px',
                    lineHeight: '1.5'
                  }}>
                    <div style={{
                      display: 'flex',
                      alignItems: 'center',
                      marginBottom: '4px',
                      fontSize: '12px',
                      opacity: '0.8'
                    }}>
                      <span style={{ marginRight: '6px' }}>
                        {message.type === 'user' 
                          ? '👤' 
                          : message.isError 
                            ? '⚠️' 
                            : message.isFallback 
                              ? '⚡' 
                              : '🤖'}
                      </span>
                      {message.type === 'user' 
                        ? 'You' 
                        : message.isError 
                          ? 'Error' 
                          : message.isFallback 
                            ? 'AI Assistant (Limited)' 
                            : 'AI Assistant'}
                    </div>
                    <div style={{
                      whiteSpace: 'pre-wrap', // Preserve line breaks in error messages
                      wordWrap: 'break-word'
                    }}>
                      {message.content}
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        {/* Input Form */}
        <form onSubmit={handleAsk} style={{
          padding: '20px 30px',
          borderTop: '1px solid #e5e7eb',
          backgroundColor: 'white',
          display: 'flex',
          gap: '12px',
          alignItems: 'flex-end'
        }}>
          <div style={{ flex: '1' }}>
            <textarea
              value={question}
              onChange={e => setQuestion(e.target.value)}
              placeholder="Ask a question about your document..."
              required
              rows="2"
              style={{
                width: '100%',
                padding: '12px 16px',
                border: '2px solid #e5e7eb',
                borderRadius: '12px',
                fontSize: '14px',
                resize: 'none',
                outline: 'none',
                transition: 'all 0.3s ease',
                boxSizing: 'border-box',
                fontFamily: 'inherit'
              }}
              onFocus={(e) => {
                e.target.style.borderColor = '#667eea';
                e.target.style.boxShadow = '0 0 0 3px rgba(102, 126, 234, 0.1)';
              }}
              onBlur={(e) => {
                e.target.style.borderColor = '#e5e7eb';
                e.target.style.boxShadow = 'none';
              }}
              onKeyDown={(e) => {
                if (e.key === 'Enter' && !e.shiftKey) {
                  e.preventDefault();
                  handleAsk(e);
                }
              }}
            />
          </div>
          <button
            type="submit"
            disabled={loading || !docId.trim() || !question.trim()}
            style={{
              padding: '12px 20px',
              background: (loading || !docId.trim() || !question.trim()) 
                ? '#d1d5db' 
                : 'linear-gradient(135deg, #667eea, #764ba2)',
              color: 'white',
              border: 'none',
              borderRadius: '12px',
              fontSize: '14px',
              fontWeight: '600',
              cursor: (loading || !docId.trim() || !question.trim()) ? 'not-allowed' : 'pointer',
              transition: 'all 0.3s ease',
              display: 'flex',
              alignItems: 'center',
              gap: '8px',
              minWidth: '80px',
              justifyContent: 'center'
            }}
            onMouseEnter={(e) => {
              if (!loading && docId.trim() && question.trim()) {
                e.target.style.transform = 'translateY(-1px)';
                e.target.style.boxShadow = '0 4px 12px rgba(102, 126, 234, 0.4)';
              }
            }}
            onMouseLeave={(e) => {
              if (!loading && docId.trim() && question.trim()) {
                e.target.style.transform = 'translateY(0)';
                e.target.style.boxShadow = 'none';
              }
            }}
          >
            {loading ? (
              <>
                <div style={{
                  width: '16px',
                  height: '16px',
                  border: '2px solid #ffffff',
                  borderTop: '2px solid transparent',
                  borderRadius: '50%',
                  animation: 'spin 1s linear infinite',
                  marginRight: '8px'
                }}></div>
                <span style={{ fontSize: '14px' }}>
                  {retryAttempt > 1 ? `Retrying (${retryAttempt}/3)...` : 'Sending...'}
                </span>
              </>
            ) : (
              <>
                🚀
                <span>Ask</span>
              </>
            )}
          </button>
        </form>

        {/* Error Display */}
        {error && (
          <div style={{
            margin: '0 30px 20px 30px',
            padding: '12px 16px',
            backgroundColor: '#fef2f2',
            border: '1px solid #fecaca',
            borderRadius: '8px',
            color: '#dc2626',
            fontSize: '14px',
            display: 'flex',
            alignItems: 'center'
          }}>
            <span style={{ marginRight: '8px' }}>❌</span>
            {error}
          </div>
        )}
      </div>

      {/* Add CSS keyframes for spinner animation */}
      <style>
        {`
          @keyframes spin {
            0% { transform: rotate(0deg); }
            100% { transform: rotate(360deg); }
          }
        `}
      </style>
    </div>
  );
}
