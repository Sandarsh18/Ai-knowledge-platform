# Doc ID Auto-Correction System

## Overview
This system automatically detects and corrects document ID mismatches between what gets stored in DynamoDB and what gets displayed to users.

## How It Works

### Backend Auto-Correction (query.py)
1. **Detection**: When a query is made, the system first tries the provided doc_id
2. **Mapping Check**: If the document isn't found, it checks against known mappings
3. **Correction**: If a mapping exists, it uses the corrected doc_id
4. **Notification**: Returns correction information to the frontend

### Frontend Auto-Correction (Chat.js)
1. **Pre-query Correction**: Checks known mappings before sending request
2. **Server Response Handling**: Processes server-side correction notifications
3. **User Feedback**: Shows visual notifications when corrections are applied
4. **State Update**: Updates the doc_id in the component state for future queries

## Current Mappings
```javascript
// Known problematic doc_id mappings
{
  '31c3fea0-1baf-43a1-823e-6070e6ef6088': '31c3fab0-1baf-41a1-837d-687bf6bfdd88'
}
```

## Features
- ✅ Automatic detection of doc_id mismatches
- ✅ Both client-side and server-side correction
- ✅ User notification with visual styling
- ✅ Automatic state updates for future queries
- ✅ Fallback to original doc_id if correction fails
- ✅ Comprehensive logging for debugging

## Adding New Mappings

### Backend (query.py)
```python
doc_id_mappings = {
    'incorrect_id': 'correct_id',
    # Add new mappings here
}
```

### Frontend (Chat.js)
```javascript
const knownDocIdMappings = {
  'incorrect_id': 'correct_id',
  // Add new mappings here
};
```

## Visual Indicators
- **Info Messages**: Light blue background with blue text
- **Error Messages**: Light red background with red text  
- **Fallback Messages**: Light amber background with amber text

## Logging
- Backend: `[DOC-ID-CORRECTION]` prefixed logs
- Frontend: Console logs with correction details
