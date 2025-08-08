import { multiAudio } from 'multiaudio';

window.testEcho = () => {
    const inputValue = document.getElementById("echoInput").value;
    multiAudio.echo({ value: inputValue })
}
