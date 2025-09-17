// Simple test of the upload endpoint
const testUpload = async () => {
  try {
    console.log('Testing upload endpoint...');
    
    // Create a simple test file
    const testContent = new Uint8Array([1, 2, 3, 4, 5]); // Simple binary data
    
    const response = await fetch('https://oq6jj8rmc9.execute-api.ap-south-1.amazonaws.com/upload', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/octet-stream',
        'x-filename': 'test.pdf',
        'Authorization': 'test-token' // Dummy token for testing
      },
      body: testContent
    });
    
    console.log('Response status:', response.status);
    console.log('Response headers:', [...response.headers.entries()]);
    
    const data = await response.text();
    console.log('Response body:', data);
    
  } catch (error) {
    console.error('Test failed:', error);
  }
};

testUpload();
