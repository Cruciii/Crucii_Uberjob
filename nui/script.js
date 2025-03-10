let timerDuration = 15000; // 5 seconds timer
let timerInterval;
let timerTimeout;

window.addEventListener('message', function(event) {
    let data = event.data;
    console.log("[myBankHack:NUI] Received message:", data);

    if (data.action === "setPuzzle") {
        // Show the terminal box and initialize fields
        document.querySelector(".terminal").style.display = "block";
        document.getElementById("instruction").innerText = data.instruction;
        document.getElementById("puzzle").innerText = data.puzzle;
        document.getElementById("result").innerText = "";
        document.getElementById("guessInput").value = "";
        document.getElementById("guessInput").focus();
        startTimer();
    }
    if (data.action === "result") {
        document.getElementById("result").innerText = data.message;
    }
    if (data.action === "hide") {
        hideTerminal();
    }
});

function startTimer() {
    let timerBar = document.getElementById("timer-bar");
    let startTime = Date.now();
    timerBar.style.width = "100%";

    // Update the progress bar every 50ms
    timerInterval = setInterval(() => {
        let elapsed = Date.now() - startTime;
        let remaining = Math.max(timerDuration - elapsed, 0);
        let percentage = (remaining / timerDuration) * 100;
        timerBar.style.width = percentage + "%";
    }, 50);

    // When time is up, notify the client and hide the UI
    timerTimeout = setTimeout(() => {
        document.getElementById("result").innerText = "Time's up!";
        setTimeout(() => {
            fetch(`https://${GetParentResourceName()}/timeout`, {
                method: 'POST',
                headers: {
                    'Content-Type': 'application/json; charset=UTF-8'
                },
                body: JSON.stringify({})
            }).then(resp => resp.json()).then(respData => {
                // Handle additional response data if needed
            });
            hideTerminal();
        }, 1000);
    }, timerDuration);
}

function hideTerminal() {
    document.querySelector(".terminal").style.display = "none";
    clearInterval(timerInterval);
    clearTimeout(timerTimeout);
    resetTimerBar();
}

function resetTimerBar() {
    let timerBar = document.getElementById("timer-bar");
    timerBar.style.width = "100%";
}

// Handle form submission and send the guess back to the client
document.getElementById("hackForm").addEventListener("submit", function(e) {
    e.preventDefault();
    let guess = document.getElementById("guessInput").value;
    fetch(`https://${GetParentResourceName()}/submit`, {
        method: 'POST',
        headers: {
            'Content-Type': 'application/json; charset=UTF-8'
        },
        body: JSON.stringify({ guess: guess })
    }).then(resp => resp.json()).then(respData => {
        // Additional response handling if needed.
    });
});