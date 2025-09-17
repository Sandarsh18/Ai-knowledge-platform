import React from 'react';
import { BrowserRouter as Router, Route, Routes, Navigate, useLocation } from 'react-router-dom';
import Login from './components/Login';
import Register from './components/Register';
import VerifyEmail from './components/VerifyEmail';
import Upload from './components/Upload';
import Chat from './components/Chat';
import './App.css';

function Navigation() {
  const location = useLocation();
  const isAuthenticated = localStorage.getItem('token');
  
  // Don't show navigation on auth pages
  if (['/login', '/register', '/verify'].includes(location.pathname)) {
    return null;
  }

  return (
    <nav style={{
      position: 'fixed',
      top: '0',
      left: '0',
      right: '0',
      zIndex: '1000',
      background: 'rgba(255, 255, 255, 0.95)',
      backdropFilter: 'blur(10px)',
      borderBottom: '1px solid rgba(0, 0, 0, 0.1)',
      padding: '12px 0'
    }}>
      <div style={{
        maxWidth: '1200px',
        margin: '0 auto',
        display: 'flex',
        alignItems: 'center',
        justifyContent: 'space-between',
        padding: '0 20px'
      }}>
        <div style={{
          display: 'flex',
          alignItems: 'center'
        }}>
          <h1 style={{
            margin: '0',
            fontSize: '24px',
            fontWeight: '700',
            background: 'linear-gradient(135deg, #667eea, #764ba2)',
            WebkitBackgroundClip: 'text',
            WebkitTextFillColor: 'transparent',
            backgroundClip: 'text'
          }}>
            🧠 AI Knowledge
          </h1>
        </div>
        
        <div style={{
          display: 'flex',
          gap: '8px',
          alignItems: 'center'
        }}>
          {isAuthenticated && (
            <>
              <a 
                href="/upload" 
                style={{
                  padding: '8px 16px',
                  textDecoration: 'none',
                  borderRadius: '8px',
                  fontSize: '14px',
                  fontWeight: '500',
                  transition: 'all 0.3s ease',
                  color: location.pathname === '/upload' ? 'white' : '#667eea',
                  backgroundColor: location.pathname === '/upload' ? '#667eea' : 'transparent',
                  border: location.pathname === '/upload' ? 'none' : '1px solid #667eea'
                }}
                onMouseEnter={(e) => {
                  if (location.pathname !== '/upload') {
                    e.target.style.backgroundColor = '#667eea';
                    e.target.style.color = 'white';
                  }
                }}
                onMouseLeave={(e) => {
                  if (location.pathname !== '/upload') {
                    e.target.style.backgroundColor = 'transparent';
                    e.target.style.color = '#667eea';
                  }
                }}
              >
                📤 Upload
              </a>
              <a 
                href="/chat" 
                style={{
                  padding: '8px 16px',
                  textDecoration: 'none',
                  borderRadius: '8px',
                  fontSize: '14px',
                  fontWeight: '500',
                  transition: 'all 0.3s ease',
                  color: location.pathname === '/chat' ? 'white' : '#667eea',
                  backgroundColor: location.pathname === '/chat' ? '#667eea' : 'transparent',
                  border: location.pathname === '/chat' ? 'none' : '1px solid #667eea'
                }}
                onMouseEnter={(e) => {
                  if (location.pathname !== '/chat') {
                    e.target.style.backgroundColor = '#667eea';
                    e.target.style.color = 'white';
                  }
                }}
                onMouseLeave={(e) => {
                  if (location.pathname !== '/chat') {
                    e.target.style.backgroundColor = 'transparent';
                    e.target.style.color = '#667eea';
                  }
                }}
              >
                💬 Chat
              </a>
              <button
                onClick={() => {
                  localStorage.removeItem('token');
                  window.location.href = '/login';
                }}
                style={{
                  padding: '8px 16px',
                  background: '#ef4444',
                  color: 'white',
                  border: 'none',
                  borderRadius: '8px',
                  fontSize: '14px',
                  fontWeight: '500',
                  cursor: 'pointer',
                  transition: 'all 0.3s ease'
                }}
                onMouseEnter={(e) => {
                  e.target.style.backgroundColor = '#dc2626';
                }}
                onMouseLeave={(e) => {
                  e.target.style.backgroundColor = '#ef4444';
                }}
              >
                🔓 Logout
              </button>
            </>
          )}
        </div>
      </div>
    </nav>
  );
}

function App() {
  return (
    <Router>
      <div className="App" style={{ minHeight: '100vh', fontFamily: '-apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif' }}>
        <Navigation />
        <div style={{ paddingTop: isAuthenticated ? '80px' : '0' }}>
          <Routes>
            <Route path="/" element={<Navigate to="/login" />} />
            <Route path="/login" element={<Login />} />
            <Route path="/register" element={<Register />} />
            <Route path="/verify" element={<VerifyEmail />} />
            <Route path="/upload" element={<Upload />} />
            <Route path="/chat" element={<Chat />} />
          </Routes>
        </div>
      </div>
    </Router>
  );
}

const isAuthenticated = localStorage.getItem('token');

export default App;
