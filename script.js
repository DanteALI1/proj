// Основная логика анимации замка
document.addEventListener('DOMContentLoaded', function () {
    const lockContainer = document.getElementById('lockContainer');
    const lockFill = document.getElementById('lockFill');
    const lockIcon = document.getElementById('lockIcon');
    const progressText = document.getElementById('progressText');
    const tocSection = document.getElementById('tocSection');
    const pageFooter = document.getElementById('pageFooter');

    // Запуск анимации после небольшой задержки
    setTimeout(startLockAnimation, 500);

    function startLockAnimation() {
        // Этап 1: Заполнение замка
        lockFill.style.clipPath = 'polygon(0% 0%, 100% 0%, 100% 100%, 0% 100%)';
        progressText.textContent = "Проверка целостности системы...";

        // Этап 2: Открытие замка
        setTimeout(() => {
            lockIcon.classList.remove('fa-lock');
            lockIcon.classList.add('fa-lock-open');
            lockIcon.style.transform = 'translate(-50%, -50%) rotate(10deg)';
            progressText.textContent = "Открытие доступа к системе безопасности...";

            // Этап 3: Завершение анимации
            setTimeout(() => {
                // Анимация исчезновения замка
                lockContainer.style.opacity = '0';
                lockContainer.style.transform = 'scale(1.2)';

                // Показ контента
                setTimeout(() => {
                    lockContainer.style.display = 'none';
                    tocSection.style.opacity = '1';
                    tocSection.style.transform = 'translateY(0)';
                    pageFooter.style.opacity = '1';
                }, 1000);
            }, 1500);
        }, 3000);
    }
});