-- For compatibility, if there are any third-party apps that rely on json library being here
return {decode = JSON.parse, encode = JSON.stringify}
