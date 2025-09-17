import React, { useState } from 'react';
import { CognitoUser } from 'amazon-cognito-identity-js';
import { userPool } from '../cognitoConfig';
import { useNavigate } from 'react-router-dom';

export default function VerifyEmail() {
  const [email, setEmail] = useState('');
  const [verificationCode, setVerificationCode] = useState('');
  const [error, setError] = useState('');
  const [success, setSuccess] = useState('');
  const [loading, setLoading] = useState(false);
  const [resending, setResending] = useState(false);
  const navigate = useNavigate();

  const handleVerify = (e) => {
    e.preventDefault();
    setLoading(true);
    setError('');
    setSuccess('');
    
    const userData = {
      Username: email,
      Pool: userPool,
    };
    
    const cognitoUser = new CognitoUser(userData);
    
    cognitoUser.confirmRegistration(verificationCode, true, (err, result) => {
      setLoading(false);
      if (err) {
        setError(err.message || 'Verification failed');
        setSuccess('');
      } else {
        setSuccess('Email verified successfully! Redirecting to login...');
        setError('');
        setTimeout(() => navigate('/login'), 2000);
      }
    });
  };

  const resendCode = () => {
    setResending(true);
    setError('');
    setSuccess('');
    
    const userData = {
      Username: email,
      Pool: userPool,
    };
    
    const cognitoUser = new CognitoUser(userData);
    
    cognitoUser.resendConfirmationCode((err, result) => {
      setResending(false);
      if (err) {
        setError(err.message || 'Failed to resend code');
      } else {
        setSuccess('Verification code sent again! Check your email.');
        setError('');
      }
    });
  };

  return (
    <div style={{
      minHeight: '100vh',
      background: 'linear-gradient(135deg, #f59e0b 0%, #d97706 100%)',
      display: 'flex',
      alignItems: 'center',
      justifyContent: 'center',
      padding: '20px'
    }}>
      <div style={{
        maxWidth: '450px',
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
          bottom: '-50px',
          right: '-50px',
          width: '120px',
          height: '120px',
          background: 'linear-gradient(135deg, #f59e0b, #d97706)',
          borderRadius: '50%',
          opacity: '0.1'
        }}></div>
        
        <div style={{ textAlign: 'center', marginBottom: '32px' }}>
          <h1 style={{
            margin: '0 0 8px 0',
            fontSize: '32px',
            fontWeight: '700',
            background: 'linear-gradient(135deg, #f59e0b, #d97706)',
            WebkitBackgroundClip: 'text',
            WebkitTextFillColor: 'transparent',
            backgroundClip: 'text'
          }}>
            📧 Verify Email
          </h1>
          <h2 style={{
            margin: '0 0 8px 0',
            fontSize: '24px',
            fontWeight: '600',
            color: '#374151'
          }}>
            Almost There!
          </h2>
          <p style={{
            margin: '0',
            color: '#6b7280',
            fontSize: '14px',
            lineHeight: '1.5'
          }}>
            Check your email for the verification code and enter it below to activate your account
          </p>
        </div>

        <form onSubmit={handleVerify} style={{ display: 'flex', flexDirection: 'column', gap: '20px' }}>
          <div>
            <label style={{
              display: 'block',
              marginBottom: '6px',
              fontSize: '14px',
              fontWeight: '500',
              color: '#374151'
            }}>
              Email Address
            </label>
            <input 
              type="email" 
              value={email} 
              onChange={e => setEmail(e.target.value)} 
              placeholder="Enter your email address" 
              required 
              style={{
                width: '100%',
                padding: '12px 16px',
                border: '2px solid #e5e7eb',
                borderRadius: '10px',
                fontSize: '16px',
                transition: 'all 0.3s ease',
                outline: 'none',
                boxSizing: 'border-box'
              }}
              onFocus={(e) => {
                e.target.style.borderColor = '#f59e0b';
                e.target.style.boxShadow = '0 0 0 3px rgba(245, 158, 11, 0.1)';
              }}
              onBlur={(e) => {
                e.target.style.borderColor = '#e5e7eb';
                e.target.style.boxShadow = 'none';
              }}
            />
          </div>

          <div>
            <label style={{
              display: 'block',
              marginBottom: '6px',
              fontSize: '14px',
              fontWeight: '500',
              color: '#374151'
            }}>
              Verification Code
            </label>
            <input 
              type="text" 
              value={verificationCode} 
              onChange={e => setVerificationCode(e.target.value)} 
              placeholder="Enter 6-digit code from email" 
              required 
              maxLength="6"
              style={{
                width: '100%',
                padding: '12px 16px',
                border: '2px solid #e5e7eb',
                borderRadius: '10px',
                fontSize: '18px',
                fontWeight: '600',
                letterSpacing: '2px',
                textAlign: 'center',
                transition: 'all 0.3s ease',
                outline: 'none',
                boxSizing: 'border-box'
              }}
              onFocus={(e) => {
                e.target.style.borderColor = '#f59e0b';
                e.target.style.boxShadow = '0 0 0 3px rgba(245, 158, 11, 0.1)';
              }}
              onBlur={(e) => {
                e.target.style.borderColor = '#e5e7eb';
                e.target.style.boxShadow = 'none';
              }}
            />
            <p style={{
              margin: '4px 0 0 0',
              fontSize: '12px',
              color: '#6b7280',
              textAlign: 'center'
            }}>
              Check your spam folder if you don't see the email
            </p>
          </div>

          <button 
            type="submit" 
            disabled={loading}
            style={{
              width: '100%',
              padding: '14px',
              background: loading ? '#d1d5db' : 'linear-gradient(135deg, #f59e0b, #d97706)',
              color: 'white',
              border: 'none',
              borderRadius: '10px',
              fontSize: '16px',
              fontWeight: '600',
              cursor: loading ? 'not-allowed' : 'pointer',
              transition: 'all 0.3s ease',
              boxShadow: loading ? 'none' : '0 4px 12px rgba(245, 158, 11, 0.4)'
            }}
            onMouseEnter={(e) => {
              if (!loading) {
                e.target.style.transform = 'translateY(-2px)';
                e.target.style.boxShadow = '0 8px 20px rgba(245, 158, 11, 0.5)';
              }
            }}
            onMouseLeave={(e) => {
              if (!loading) {
                e.target.style.transform = 'translateY(0)';
                e.target.style.boxShadow = '0 4px 12px rgba(245, 158, 11, 0.4)';
              }
            }}
          >
            {loading ? (
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
                Verifying...
              </div>
            ) : '✅ Verify Email'}
          </button>

          <button 
            type="button"
            onClick={resendCode} 
            disabled={!email || resending}
            style={{
              width: '100%',
              padding: '12px',
              background: resending ? '#d1d5db' : 'transparent',
              color: resending ? '#9ca3af' : '#6b7280',
              border: '2px solid #e5e7eb',
              borderRadius: '10px',
              fontSize: '14px',
              fontWeight: '600',
              cursor: (!email || resending) ? 'not-allowed' : 'pointer',
              transition: 'all 0.3s ease'
            }}
            onMouseEnter={(e) => {
              if (!resending && email) {
                e.target.style.borderColor = '#f59e0b';
                e.target.style.color = '#f59e0b';
              }
            }}
            onMouseLeave={(e) => {
              if (!resending && email) {
                e.target.style.borderColor = '#e5e7eb';
                e.target.style.color = '#6b7280';
              }
            }}
          >
            {resending ? (
              <div style={{ display: 'flex', alignItems: 'center', justifyContent: 'center' }}>
                <div style={{
                  width: '16px',
                  height: '16px',
                  border: '2px solid #9ca3af',
                  borderTop: '2px solid transparent',
                  borderRadius: '50%',
                  animation: 'spin 1s linear infinite',
                  marginRight: '8px'
                }}></div>
                Sending...
              </div>
            ) : '🔄 Resend Code'}
          </button>

          {error && (
            <div style={{
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

          {success && (
            <div style={{
              padding: '12px 16px',
              backgroundColor: '#f0fdf4',
              border: '1px solid #bbf7d0',
              borderRadius: '8px',
              color: '#166534',
              fontSize: '14px',
              display: 'flex',
              alignItems: 'center'
            }}>
              <span style={{ marginRight: '8px' }}>✅</span>
              {success}
            </div>
          )}
        </form>

        <div style={{
          marginTop: '32px',
          textAlign: 'center',
          padding: '20px',
          backgroundColor: '#f8fafc',
          borderRadius: '12px'
        }}>
          <p style={{ margin: '0 0 12px 0', fontSize: '14px', color: '#64748b' }}>
            Already verified your email?
          </p>
          <div style={{ display: 'flex', gap: '12px', justifyContent: 'center' }}>
            <a 
              href="/login" 
              style={{
                display: 'inline-block',
                padding: '8px 16px',
                background: 'linear-gradient(135deg, #667eea, #764ba2)',
                color: 'white',
                textDecoration: 'none',
                borderRadius: '8px',
                fontSize: '14px',
                fontWeight: '600',
                transition: 'all 0.3s ease'
              }}
              onMouseEnter={(e) => {
                e.target.style.transform = 'translateY(-1px)';
                e.target.style.boxShadow = '0 4px 12px rgba(102, 126, 234, 0.4)';
              }}
              onMouseLeave={(e) => {
                e.target.style.transform = 'translateY(0)';
                e.target.style.boxShadow = 'none';
              }}
            >
              Sign In
            </a>
            <a 
              href="/register" 
              style={{
                display: 'inline-block',
                padding: '8px 16px',
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
              Create Account
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
