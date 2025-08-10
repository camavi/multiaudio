import { MultiAudio } from 'multiaudio';

window.testEcho = () => {
    const inputValue = document.getElementById("echoInput").value;
    MultiAudio.echo({ value: inputValue })
}
