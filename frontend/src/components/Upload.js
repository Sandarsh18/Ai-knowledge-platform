import React, { useState } from 'react';
import { useNavigate } from 'react-router-dom';

export default function Upload() {
  const [file, setFile] = useState(null);
  const [message, setMessage] = useState('');
  const [uploading, setUploading] = useState(false);
  const navigate = useNavigate();

  const handleFileChange = (e) => setFile(e.target.files[0]);

  const handleUpload = async (e) => {
    e.preventDefault();
    if (!file) {
      setMessage('Please select a PDF file');
      return;
    }

    const token = localStorage.getItem('token');
    if (!token) {
      setMessage('Please login first');
      navigate('/login');
      return;
    }

    setUploading(true);
    setMessage('Uploading...');

        try {
            console.log('Starting upload...', { fileName: file.name, fileSize: file.size });
            console.log('API URL:', process.env.REACT_APP_API_URL);
            console.log('Token exists:', !!token);
            
            const formData = await file.arrayBuffer();
            console.log('File buffer size:', formData.byteLength);
            
            // Add the filename and auth as query parameters to avoid preflight
            const uploadUrl = `${process.env.REACT_APP_API_URL}/upload?filename=${encodeURIComponent(file.name)}&auth=${encodeURIComponent(token)}`;
            
            const res = await fetch(uploadUrl, {
                method: 'POST',
                headers: {
                  'Content-Type': 'application/pdf',
                },
                body: new Uint8Array(formData),
            });
            
            console.log('Response status:', res.status);
            console.log('Response headers:', res.headers);      if (!res.ok) {
        if (res.status === 401) {
          setMessage('Authentication failed. Please login again.');
          localStorage.removeItem('token');
          navigate('/login');
          return;
        }
        throw new Error(`HTTP ${res.status}: ${res.statusText}`);
      }

      const data = await res.json();
      console.log('Upload response data:', data);
      console.log('Received doc_id:', data.doc_id);
      setMessage(`Upload successful! Document ID: ${data.doc_id}`);
    } catch (error) {
      console.error('Upload error details:', error);
      console.error('Error type:', error.constructor.name);
      console.error('Error message:', error.message);
      setMessage(`Error: ${error.message || 'Upload failed'}`);
    } finally {
      setUploading(false);
    }
  };

  return (
    <div style={{
      minHeight: '100vh',
      background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
      padding: '20px',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center'
    }}>
      <div style={{
        maxWidth: '500px',
        width: '100%',
        background: 'white',
        borderRadius: '16px',
        boxShadow: '0 20px 40px rgba(0,0,0,0.1)',
        padding: '40px',
        position: 'relative',
        overflow: 'hidden'
      }}>
        {/* Background decoration */}
        <div style={{
          position: 'absolute',
          top: '-50px',
          right: '-50px',
          width: '100px',
          height: '100px',
          background: 'linear-gradient(135deg, #667eea, #764ba2)',
          borderRadius: '50%',
          opacity: '0.1'
        }}></div>
        
        <form onSubmit={handleUpload}>
          <div style={{ textAlign: 'center', marginBottom: '30px' }}>
            <h2 style={{
              margin: '0',
              fontSize: '28px',
              fontWeight: '700',
              background: 'linear-gradient(135deg, #667eea, #764ba2)',
              WebkitBackgroundClip: 'text',
              WebkitTextFillColor: 'transparent',
              backgroundClip: 'text'
            }}>
              📄 Upload PDF
            </h2>
            <p style={{
              margin: '8px 0 0 0',
              color: '#6b7280',
              fontSize: '14px'
            }}>
              Upload your PDF to add it to your knowledge base
            </p>
          </div>

          <div style={{
            marginBottom: '24px',
            position: 'relative'
          }}>
            <div style={{
              border: file ? '2px solid #10b981' : '2px dashed #d1d5db',
              borderRadius: '12px',
              padding: '40px 20px',
              textAlign: 'center',
              backgroundColor: file ? '#f0fdf4' : '#f9fafb',
              transition: 'all 0.3s ease',
              cursor: 'pointer',
              position: 'relative',
              overflow: 'hidden'
            }}
            onClick={() => document.getElementById('fileInput').click()}
            onDragOver={(e) => {
              e.preventDefault();
              e.currentTarget.style.backgroundColor = '#f0fdf4';
              e.currentTarget.style.borderColor = '#10b981';
            }}
            onDragLeave={(e) => {
              e.preventDefault();
              e.currentTarget.style.backgroundColor = file ? '#f0fdf4' : '#f9fafb';
              e.currentTarget.style.borderColor = file ? '#10b981' : '#d1d5db';
            }}
            onDrop={(e) => {
              e.preventDefault();
              const files = e.dataTransfer.files;
              if (files.length > 0 && files[0].type === 'application/pdf') {
                setFile(files[0]);
              }
              e.currentTarget.style.backgroundColor = '#f0fdf4';
              e.currentTarget.style.borderColor = '#10b981';
            }}
            >
              <input 
                id="fileInput"
                type="file" 
                accept="application/pdf" 
                onChange={handleFileChange} 
                required 
                style={{ display: 'none' }}
              />
              
              {file ? (
                <div>
                  <div style={{ fontSize: '48px', marginBottom: '12px' }}>✅</div>
                  <div style={{ 
                    fontSize: '16px', 
                    fontWeight: '600', 
                    color: '#059669',
                    marginBottom: '4px'
                  }}>
                    {file.name}
                  </div>
                  <div style={{ fontSize: '14px', color: '#6b7280' }}>
                    {(file.size / 1024 / 1024).toFixed(2)} MB
                  </div>
                </div>
              ) : (
                <div>
                  <div style={{ fontSize: '48px', marginBottom: '12px' }}>📎</div>
                  <div style={{ 
                    fontSize: '16px', 
                    fontWeight: '600', 
                    color: '#374151',
                    marginBottom: '4px'
                  }}>
                    Click to browse or drag & drop
                  </div>
                  <div style={{ fontSize: '14px', color: '#6b7280' }}>
                    PDF files only • Max 10MB
                  </div>
                </div>
              )}
            </div>
          </div>

          <button 
            type="submit" 
            disabled={uploading || !file}
            style={{ 
              width: '100%', 
              padding: '16px', 
              fontSize: '16px',
              fontWeight: '600',
              background: uploading || !file ? '#d1d5db' : 'linear-gradient(135deg, #667eea, #764ba2)',
              color: 'white', 
              border: 'none', 
              borderRadius: '12px',
              cursor: uploading || !file ? 'not-allowed' : 'pointer',
              transition: 'all 0.3s ease',
              transform: uploading ? 'none' : 'translateY(0)',
              boxShadow: uploading || !file ? 'none' : '0 4px 12px rgba(102, 126, 234, 0.4)'
            }}
            onMouseEnter={(e) => {
              if (!uploading && file) {
                e.target.style.transform = 'translateY(-2px)';
                e.target.style.boxShadow = '0 8px 20px rgba(102, 126, 234, 0.5)';
              }
            }}
            onMouseLeave={(e) => {
              if (!uploading && file) {
                e.target.style.transform = 'translateY(0)';
                e.target.style.boxShadow = '0 4px 12px rgba(102, 126, 234, 0.4)';
              }
            }}
          >
            {uploading ? (
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <div style={{
                  width: '20px',
                  height: '20px',
                  border: '2px solid #ffffff',
                  borderTop: '2px solid transparent',
                  borderRadius: '50%',
                  animation: 'spin 1s linear infinite',
                  marginRight: '8px'
                }}></div>
                Uploading...
              </div>
            ) : 'Upload PDF'}
          </button>

          {message && (
            <div style={{
              marginTop: '20px', 
              padding: '16px', 
              borderRadius: '12px',
              fontSize: '14px',
              fontWeight: '500',
              backgroundColor: message.includes('Error') || message.includes('failed') ? '#fef2f2' : '#f0fdf4',
              color: message.includes('Error') || message.includes('failed') ? '#dc2626' : '#059669',
              border: `1px solid ${message.includes('Error') || message.includes('failed') ? '#fecaca' : '#bbf7d0'}`,
              display: 'flex',
              alignItems: 'center'
            }}>
              <span style={{ marginRight: '8px', fontSize: '16px' }}>
                {message.includes('Error') || message.includes('failed') ? '❌' : '✅'}
              </span>
              {message}
            </div>
          )}
        </form>

        <div style={{
          marginTop: '32px',
          padding: '20px',
          backgroundColor: '#f8fafc',
          borderRadius: '12px',
          textAlign: 'center'
        }}>
          <p style={{ margin: '0 0 16px 0', fontSize: '14px', color: '#64748b' }}>
            Ready to explore your knowledge base?
          </p>
          <div style={{ display: 'flex', gap: '12px', justifyContent: 'center' }}>
            <a 
              href="/chat" 
              style={{
                display: 'inline-block',
                padding: '10px 20px',
                background: 'linear-gradient(135deg, #10b981, #059669)',
                color: 'white',
                textDecoration: 'none',
                borderRadius: '8px',
                fontSize: '14px',
                fontWeight: '600',
                transition: 'all 0.3s ease'
              }}
              onMouseEnter={(e) => {
                e.target.style.transform = 'translateY(-1px)';
                e.target.style.boxShadow = '0 4px 12px rgba(16, 185, 129, 0.4)';
              }}
              onMouseLeave={(e) => {
                e.target.style.transform = 'translateY(0)';
                e.target.style.boxShadow = 'none';
              }}
            >
              💬 Go to Chat
            </a>
            <a 
              href="/login" 
              style={{
                display: 'inline-block',
                padding: '10px 20px',
                background: '#e5e7eb',
                color: '#374151',
                textDecoration: 'none',
                borderRadius: '8px',
                fontSize: '14px',
                fontWeight: '600',
                transition: 'all 0.3s ease'
              }}
              onMouseEnter={(e) => {
                e.target.style.backgroundColor = '#d1d5db';
              }}
              onMouseLeave={(e) => {
                e.target.style.backgroundColor = '#e5e7eb';
              }}
            >
              🔓 Logout
            </a>
          </div>
        </div>
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
